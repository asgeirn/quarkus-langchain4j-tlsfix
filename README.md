# quarkus-langchain4j openai TLS-config reproducer

Minimal Quarkus app that demonstrates the bug fixed by
[quarkiverse/quarkus-langchain4j#2380](https://github.com/quarkiverse/quarkus-langchain4j/pull/2380):
`quarkus.langchain4j.openai.tls-configuration-name` can be silently dropped, causing the
OpenAI client to fall back to `SSLContext.getDefault()` instead of the named
`quarkus.tls.<name>.*` bucket.

## What this project does

- A `Greeter` `@RegisterAiService` interface and a `/greet` JAX-RS endpoint that calls it.
- `application.properties` points the OpenAI base URL at a local Caddy reverse proxy
  (`https://127.0.0.1:10443/v1`) terminated with an mkcert-issued certificate, and selects
  a custom TLS bucket (`quarkus.langchain4j.openai.tls-configuration-name=custom`) whose
  trust store is `rootCA.pem`.
- Caddy proxies onward to `https://api.openai.com`.
- A toggle in `code-with-quarkus/build.gradle.kts` (`OPENAI_COMMON_TLSFIX=true|false`,
  default `false`) swaps between the upstream `quarkus-langchain4j-openai-common:1.8.4`
  jar and a locally-patched `1.8.4-tlsfix` build that contains the PR #2380 fix. The
  patched build is produced from the `quarkus-langchain4j/` git submodule and resolved
  from the local Maven repository.

The intent is: with the unpatched jar the call should fail with `PKIX path building
failed`; with the patched jar it should succeed.

## Why reproducing the bug is fragile

Two independent pitfalls can mask the bug and make the unpatched jar appear to
"just work":

1. **mkcert installs its root CA into the JDK trust store.** When `mkcert -install`
   runs with `JAVA_HOME` set, it adds the development CA to
   `$JAVA_HOME/lib/security/cacerts`. After that, even if `tls-configuration-name` is
   silently dropped and the client falls back to `SSLContext.getDefault()`, the
   handshake still succeeds — the JDK default trust store now contains the mkcert
   root, so the custom TLS bucket is no longer required for the connection to work.

   `setup.sh` already guards against this by `unset JAVA_HOME` before running
   `mkcert -install`, but if mkcert was previously installed against a JDK on this
   machine the CA may already be in that JDK's `cacerts`. To actually observe the
   bug, verify the mkcert root is NOT present in the cacerts of the JVM that runs
   the app — list with `keytool -list -keystore $JAVA_HOME/lib/security/cacerts
   -storepass changeit | grep -i mkcert`, and remove with `keytool -delete -alias
   <alias> ...` if found, or run on a JDK where mkcert never installed it.

2. **The cross-thread `ThreadLocal` hack only fails when builder and client run on
   different threads.** `AdditionalPropertiesHack` is a `ThreadLocal<Map<String,String>>`
   created with `ThreadLocal.withInitial(HashMap::new)`, so every thread observes a
   non-null (but initially empty) map. The flow is:

   - The model builder's `build()` (e.g. `QuarkusOpenAiChatModelBuilderFactory.Builder.build`)
     calls `AdditionalPropertiesHack.setTlsConfigurationName(...)`, writing into the
     map of *the calling thread*.
   - Inside `super.build()`, the OpenAI client builder calls
     `AdditionalPropertiesHack.getAndClearTlsConfigurationName()`, reading from the
     map of *its calling thread*.

   The class's own Javadoc concedes the assumption: *"Setting up a model builder
   always precedes setting up a client builder on the same thread."* When that holds —
   the typical case for a single chat model created during a single synthetic-bean
   instantiation — the value round-trips and TLS works. When it does not (model
   built on thread A, client constructed on thread B; lazy or deferred client
   creation; concurrent bean creation across multiple model kinds), thread B's
   fresh empty map yields `null`, the TLS configuration name is silently dropped,
   and the client falls back to `SSLContext.getDefault()`.

   A single `@RegisterAiService` chat model invoked from one HTTP request, as in
   this project, will normally NOT trigger the cross-thread split on its own. To
   observe the failure you generally need a workload that decouples the two
   threads — e.g. multiple model kinds (chat + embedding + streaming) being
   created concurrently, or a deployment path where client construction is
   deferred onto a different executor.

## Repository layout

- `code-with-quarkus/` — the Quarkus reproducer app (Gradle build).
  - `src/main/java/com/acme/Greeter.java` — the `@RegisterAiService` interface.
  - `src/main/java/com/acme/GreeterCli.java` — `GET /greet` calling the service.
  - `src/main/resources/application.properties` — custom TLS bucket configuration.
  - `build.gradle.kts` — `useTlsFix` toggle that substitutes the common artifact with
    the locally-installed `1.8.4-tlsfix` build.
- `quarkus-langchain4j/` — git submodule pointing at the patched
  [asgeirn/quarkus-langchain4j](https://github.com/asgeirn/quarkus-langchain4j) fork
  that carries the PR #2380 fix as version `1.8.4-tlsfix`. Must be installed to
  `~/.m2` for the patched build to be resolvable.
- `Caddyfile` / `setup.sh` / `greet.sh` — local TLS-terminating proxy and helpers.

## Running

```shell
./setup.sh                # downloads caddy + mkcert, generates certs,
                          # inits the submodule and installs 1.8.4-tlsfix to mavenLocal
./caddy run               # terminal 1

cd code-with-quarkus
OPENAI_COMMON_TLSFIX=false ./gradlew quarkusRun   # terminal 2 (unpatched)
curl http://localhost:8080/greet
```

Switch `OPENAI_COMMON_TLSFIX` to `true` to use the patched jar from mavenLocal. To make
the difference visible, first ensure the mkcert root is not in the JDK's `cacerts`.
