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

Two independent pitfalls make the unpatched jar appear to "just work":

1. **mkcert installs its root CA into the JDK trust store.** When `mkcert -install` runs
   with `JAVA_HOME` set, it adds the development CA to `$JAVA_HOME/lib/security/cacerts`.
   After that, even if `tls-configuration-name` is silently dropped and the client falls
   back to `SSLContext.getDefault()`, the handshake still succeeds — the JDK default trust
   store happens to contain the mkcert root.

   To actually observe the bug, the mkcert CA must NOT be in the JDK trust store of the
   JVM that runs the app (remove it with `keytool -delete -alias mkcert... -keystore
   $JAVA_HOME/lib/security/cacerts -storepass changeit`, or run on a JDK where mkcert
   never installed it).

2. **The threading bug requires a specific class-loading order.**
   `AdditionalPropertiesHack` stores properties in a `ThreadLocal<Map>` populated by a
   *static initializer*, so only the class-loading thread ever sees a non-null map.
   `OpenAiRecorder` calls `builder.build()` (which is what triggers loading of
   `AdditionalPropertiesHack`) inside the synthetic-bean creator's `Function.apply()`. With
   only a single OpenAI model bean, class loading and bean creation happen on the same
   thread, the `ThreadLocal` is populated, and `setTlsConfigurationName(...)` works.

   The bug surfaces when `AdditionalPropertiesHack` is loaded on thread A but bean
   creation happens on thread B — e.g. multiple model kinds (chat + embedding +
   streaming) created on different threads, or anything that touches the class earlier on
   the main thread. A single `@RegisterAiService` exercising one chat model from one HTTP
   request, as in this project, does not trigger it on its own.

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
