#!/bin/bash

# Setup script for bug reproduction environment
set -e

echo "=== Setting up bug reproduction environment ==="

# Check if caddy and mkcert are already downloaded
if [ ! -f "caddy" ]; then
    echo "Downloading caddy..."
    curl -L -o caddy "https://github.com/caddyserver/caddy/releases/latest/download/caddy_$(uname -s)_$(uname -m)"
    chmod +x caddy
else
    echo "Caddy already exists, skipping download"
fi

# Check if mkcert binary exists
if [ ! -f "mkcert" ]; then
    echo "Downloading mkcert..."
    # Determine OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        darwin) OS="darwin" ;;
        linux) OS="linux" ;;
        *) echo "Unsupported OS: $OS"; exit 1 ;;
    esac

    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    MKCERT_URL="https://dl.filippo.io/mkcert/latest?for=$OS/$ARCH"
    curl -L -o mkcert "$MKCERT_URL"
    chmod +x mkcert
fi

# Generate certificates if they don't exist
if [ ! -f "rootCA.pem" ] || [ ! -f "localhost.pem" ] || [ ! -f "localhost-key.pem" ]; then
    echo "Generating certificates..."
    # Unset JAVA_HOME to prevent mkcert from modifying JVM cacerts
    unset JAVA_HOME
    ./mkcert -install
    ./mkcert -cert-file localhost.pem -key-file localhost-key.pem localhost 127.0.0.1 ::1
    cp "$(./mkcert -CAROOT)/rootCA.pem" ./
else
    echo "Certificates already exist, skipping generation"
fi

# Build and install the patched quarkus-langchain4j to mavenLocal so the
# OPENAI_COMMON_TLSFIX=true path can resolve 1.8.4-tlsfix.
TLSFIX_ARTIFACT="$HOME/.m2/repository/io/quarkiverse/langchain4j/quarkus-langchain4j-openai-common/1.8.4-tlsfix"
if [ ! -d "$TLSFIX_ARTIFACT" ]; then
    echo "Initializing quarkus-langchain4j submodule..."
    git submodule update --init --recursive

    echo "Installing patched quarkus-langchain4j 1.8.4-tlsfix to mavenLocal (this takes a few minutes)..."
    (cd quarkus-langchain4j && ./mvnw install -DskipTests)
else
    echo "Patched quarkus-langchain4j 1.8.4-tlsfix already installed in mavenLocal, skipping build"
fi

echo "=== Environment setup complete ==="
echo "To test the bug reproduction:"
echo ""
echo "1. In terminal 1, start Caddy:"
echo "   ./caddy run"
echo ""
echo "2. In terminal 2, test WITHOUT the fix:"
echo "   cd code-with-quarkus && OPENAI_COMMON_TLSFIX=false ./gradlew quarkusRun"
echo "   Then call: curl -v http://localhost:8080/greet"
echo ""
echo "3. In terminal 2, test WITH the fix:"
echo "   cd code-with-quarkus && OPENAI_COMMON_TLSFIX=true ./gradlew quarkusRun"
echo "   Then call: curl -v http://localhost:8080/greet"
