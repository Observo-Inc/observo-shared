#!/bin/bash

while getopts "e:" opt; do
    case "$opt" in
        e) env_var="$OPTARG" ;;  # Capture value after -e
        *) echo "Usage: $0 -e 'install_id=<JWT Token>'"; exit 1 ;;
    esac
done

if [[ -z "$env_var" ]]; then
    echo "Error: Missing -e argument"
    exit 1
fi

echo "Received environment variable: $env_var"

# Extract the install_id from the input
if [[ "$env_var" =~ install_id=([^ ]+) ]]; then
    TOKEN="${BASH_REMATCH[1]}"
    echo "Extracted install_id: $install_id"
else
    echo "Error: install_id not found in argument"
    exit 1
fi


# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     OS=linux;;
    Darwin*)    OS=darwin;;
    CYGWIN*|MINGW*|MSYS*) OS=windows;;
    *)          OS=unknown;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)    ARCH=amd64;;
    arm64|aarch64)   ARCH=arm64;;  # Add support for Apple Silicon
    armv7l)    ARCH=armv7;;
    i386|i686) ARCH=386;;
    *)         ARCH=unknown;;
esac

# Print detected values
echo "Detected OS: $OS"
echo "Detected Architecture: $ARCH"

# Construct download URL
if [[ "$OS" == "unknown" || "$ARCH" == "unknown" ]]; then
    echo "Unsupported OS or architecture."
    exit 1
fi

# Extract the payload
PAYLOAD_ENCODED=$(echo -n "$TOKEN" | cut -d "." -f2)

# Replace Base64 URL-safe characters with standard Base64 characters
PAYLOAD_ENCODED=$(echo "$PAYLOAD_ENCODED" | tr '_-' '/+')

# Fix padding (add = if necessary)
PAYLOAD_ENCODED=$(echo "$PAYLOAD_ENCODED" | sed 's/\(.*\)/\1\=\=/')

# Decode the payload
PAYLOAD=$(echo "$PAYLOAD_ENCODED" | base64 -d 2>/dev/null)


# Extracting values using jq
SITE_ID=$(echo $PAYLOAD | jq -r '.site_id')
SECRET=$(echo $PAYLOAD | jq -r '.secret')
VERSION=$(echo $PAYLOAD | jq -r '.version')

echo "SITE_ID: $SITE_ID"
echo "SECRET: $SECRET"
echo "VERSION: $VERSION"

PACKAGE_NAME="otelcol-contrib"


# https://github.com/open-telemetry/opentelemetry-collector-releases/releases
BASE_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"
PACKAGE="${PACKAGE_NAME}_${VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="${BASE_URL}/v${VERSION}/${PACKAGE}"
echo "downloading from $DOWNLOAD_URL"

if ! curl --head -s -L "$DOWNLOAD_URL" | grep -q "HTTP/2 200"; then
    echo "File does not exist. Something has gone wrong"
    exit 1
fi

curl -LO "$DOWNLOAD_URL"

## un tar the file
## next steps
