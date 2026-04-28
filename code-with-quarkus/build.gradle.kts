plugins {
    java
    id("io.quarkus")
}

val quarkusPlatformGroupId: String by project
val quarkusPlatformArtifactId: String by project
val quarkusPlatformVersion: String by project

// Set OPENAI_COMMON_TLSFIX=false (env or -P) to use the upstream 1.8.4 jar instead of the patched -tlsfix build.
// Tracked upstream at https://github.com/quarkiverse/quarkus-langchain4j/pull/2380 — remove once released.
val useTlsFix = (System.getenv("OPENAI_COMMON_TLSFIX")
    ?: project.findProperty("openaiCommonTlsfix")?.toString()
    ?: "false").toBoolean()
logger.lifecycle("Using local TLS fix jar: $useTlsFix")

repositories {
    mavenCentral()
}

dependencies {
    implementation(enforcedPlatform("${quarkusPlatformGroupId}:${quarkusPlatformArtifactId}:${quarkusPlatformVersion}"))
    // Non-enforced platform so the strict version below can override the BOM-managed 1.8.4.
    implementation(platform("${quarkusPlatformGroupId}:quarkus-langchain4j-bom:${quarkusPlatformVersion}"))
    implementation("io.quarkiverse.langchain4j:quarkus-langchain4j-core")
    implementation("io.quarkus:quarkus-rest")
    if (useTlsFix) {
        // Use local patched jar from libs/ directory
        implementation(files("libs/quarkus-langchain4j-openai-common-1.8.4-tlsfix.jar"))
        // The local JAR might need explicit dependencies
        implementation("dev.langchain4j:langchain4j-openai:0.29.4")
    } else {
        // Use version from mavenCentral (managed by BOM)
        implementation("io.quarkiverse.langchain4j:quarkus-langchain4j-openai-common")
    }
    implementation("io.quarkiverse.langchain4j:quarkus-langchain4j-openai") {
        exclude(group = "io.quarkiverse.langchain4j", module = "quarkus-langchain4j-openai-common")
    }
    testImplementation("io.quarkus:quarkus-junit")
}

group = "org.acme"
version = "1.0.0-SNAPSHOT"

java {
    sourceCompatibility = JavaVersion.VERSION_25
    targetCompatibility = JavaVersion.VERSION_25
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-parameters")
}

/*
tasks.named<io.quarkus.gradle.tasks.QuarkusRun>("quarkusRun") {
    jvmArgs = listOf("-Djavax.net.debug=ssl:handshake:trustmanager")
}
*/
