#!/bin/bash

PREREQS="sudo curl jq"
INSTALL_DIR="/opt/observo"
TMP_DIR="/tmp/observo"
CONFIG_DIR="/opt/observo"
TAR_FILE="$TMP_DIR"/edge.tar.gz
EXTRACT_DIR="$CONFIG_DIR/edge"
EXEC_PATH="$INSTALL_DIR"/edge
PACKAGE_NAME="otelcol-contrib"
CONFIG_FILE="$CONFIG_DIR"/edge-config.json
BASE_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"
    

dependencies_check() {
    echo "Checking for script dependencies..."
    
    # Detect package manager
    if command -v apt &>/dev/null; then
        sudo apt-get update
        PKG_MANAGER="sudo apt-get install -y"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="sudo yum install -y"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="sudo dnf install -y"
    elif command -v brew &>/dev/null; then
        PKG_MANAGER="brew install"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="sudo apk add"
    else
        echo "Unsupported package manager. Install dependencies manually."
        exit 1
    fi

    $PKG_MANAGER $cmd || { echo "Failed to install $cmd"; exit 1; }
    
    # Check for missing dependencies
    for cmd in $PREREQS; do
        if ! command -v $cmd &>/dev/null; then
            echo "$cmd is missing. Installing..."
            $PKG_MANAGER $cmd || { echo "Failed to install $cmd"; exit 1; }
        else
            echo "$cmd is already installed."
        fi
    done
}

parse_environment_variable() {
    local env_var=""  # Make env_var local to the function
    while getopts "e:" opt; do
        case "$opt" in
            e) env_var="$OPTARG";;
            *) echo "Usage: $0 -e 'install_id=<JWT Token>'"; return 1;; # Return error code
        esac
    done

    # Reset OPTIND to 1.  This is CRUCIAL!
    OPTIND=1

    if [[ -z "$env_var" ]]; then
        echo "Error: Missing -e argument"
        return 1 # Return error code
    fi

    echo "Received environment variable: $env_var"

    # Correct the regular expression to capture only the value after install_id=
    if [[ "$env_var" =~ install_id=([A-Za-z0-9+/=]+) ]]; then
        TOKEN="${BASH_REMATCH[1]}"  # Extract the base64-encoded token value
        echo "Extracted install_id (base64): $TOKEN"
        
        # Decode the base64 string
        DECODED=$(echo "$TOKEN" | base64 --decode)
        echo "Decoded install_id (JSON): $DECODED"

        export TOKEN # Make TOKEN available to other functions. Crucial!
        return 0 # Success
    else
        echo "Error: install_id not found in argument"
        return 1 # Failure
    fi
}

detect_system() {
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)     OS=linux;;
        Darwin*)    OS=darwin;;
        CYGWIN*|MINGW*|MSYS*) OS=windows;;
        *)          OS=unknown;;
    esac

    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)    ARCH=amd64;;
        arm64|aarch64)   ARCH=arm64;;
        armv7l)    ARCH=armv7;;
        i386|i686) ARCH=386;;
        *)         ARCH=unknown;;
    esac

    echo "Detected OS: $OS"
    echo "Detected Architecture: $ARCH"

    if [[ "$OS" == "unknown" || "$ARCH" == "unknown" ]]; then
        echo "Unsupported OS or architecture."
        exit 1
    fi
}

decode_and_extract_config() {
    echo "token $TOKEN"
    # Handle padding
    PADDING=$(( 4 - (${#TOKEN} % 4) ))
    if [[ $PADDING -gt 0 ]]; then
        TOKEN+=$(printf '=' %.s "" $(seq 1 $PADDING))
    fi

    # TODO CHECK THIS
    PAYLOAD=$(echo "$TOKEN" | base64 -d)

    mkdir -p "$CONFIG_DIR"
    echo "$PAYLOAD" > "$CONFIG_FILE" # Directly write payload to file

    SITE_ID=$(echo "$PAYLOAD" | jq -r '.site_id')
    AUTH_TOKEN=$(echo "$PAYLOAD" | jq -r '.auth_token')
    AGENT_VERSION=$(echo "$PAYLOAD" | jq -r '.agent_version')
    CONFIG_VERSION_ID=$(echo "$PAYLOAD" | jq -r '.config_version_id')
    FLEET_ID=$(echo "$PAYLOAD" | jq -r '.fleet_id')
    PLATFORM=$(echo "$PAYLOAD" | jq -r '.platform')
    EDGE_MANAGER_URL=$(echo "$PAYLOAD" | jq -r '.edge_manager_url')

    echo "SITE_ID: $SITE_ID"
    echo "AUTH_TOKEN: $AUTH_TOKEN"
    echo "AGENT_VERSION: $AGENT_VERSION"
    echo "CONFIG_VERSION_ID: $CONFIG_VERSION_ID"
    echo "FLEET_ID: $FLEET_ID"
    echo "PLATFORM: $PLATFORM"
    echo "EDGE_MANAGER_URL: $EDGE_MANAGER_URL"
}


download_and_extract_agent() {
    PACKAGE="${PACKAGE_NAME}_${VERSION}_${OS}_${ARCH}.tar.gz"

    #TODO: remove this and point to our repo
    # DOWNLOAD_URL="${BASE_URL}/v${VERSION}/${PACKAGE}"
    DOWNLOAD_URL="https://observo-service-images.s3.us-east-1.amazonaws.com/edge-binaries/edge-binaries.tar.gz?response-content-disposition=inline&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Security-Token=IQoJb3JpZ2luX2VjENT%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJHMEUCIFln1eCOPKQxanXrkdfkVpVf%2FuYjPKHkeli65%2BLP4uYBAiEAv62GY96vSr%2FOOcgQdU3wKVbHW%2FX9kOV5mEBIzj526dQq6wMI7f%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FARABGgw4MjI0MzQzNDY5MzkiDELpCHBy4ba8huRiOSq%2FAzOVCUXS%2FiPioSLAxJLkGXvRzx6mjPl3qValPg%2FCDxo%2BiozKBxJm%2FaN2lYhAsZOqQc%2BjgZHmypqkQUKhZGJy0sFHJGsfPR9KOToaVj4BGR5TeJ4bjSjofVT7uVAdZW4YhaE6%2FxZ3Qq4tRwjy2qGsDFULmfe7HMx1oSqnk7OSfyb1aThDl5qwHykf8f92%2BdH40NsDNUd8M0HCA0Xh7g9%2By4GxAIw3cs%2BXW2ndOz7bIyfrw8CIlWg8CrB9Bi%2FpXvf7J20Jn486KYqSD%2BxV0%2Fo48fnnHh4PIbvwo3UoyuEPeXzaKmqIjPKfXGbPDxqWq7KbRF%2FNpJ%2BtrqXpMiOxEShNTrECr%2BNTrKI03LphOp372BCU%2FOMckkG6QiLsIFF%2BBeSxcrHVBuk3ahFjjsidODFKPZsbJflkhavNjXzj4jeOb6Ru%2FjTCSrTcvEFcSv1IvR9VpTEnHGVvwgf0Y6VE57AGzkWI0ki%2FMgc22w7Y%2Fc5d8MrA%2Fz1q%2FacjfvKRi3o98okh6rdIsOloTQlt51ulfC36TnWjS8REPexD8oFUvfULjvNLZ7QufXyHVXBS7dn94HPFpoX57QZKmKOiGX7cOdnITTDr37G9BjrkAgf5bGY7pDoHQxRLehIxSChjTpUQ5eWbf3%2BFyeTqERCAMe%2B7vZc%2B7Em2HoSJ0cr6cM4yTEs8oXDEn4war8OphqofjpQ13%2BKc6yYSiQ%2BlrTXlVH5nCS%2Bb55zV2vHdRKjZBzX93sRwQWps9TQHxxerYgbxEygtiksBd7HSXWfG4g0MEQAcqkMopCu5QIqdX6VIcwqieRrnuXFUXwOMnO4%2BGxYmuf7vF5HaeRuRV8dEmlob%2FuhNcgGRfZRS6fvhMq6aNrt5qgBpiUC06RCQXSA54THdjB5qKgFOHqXRouNt0gCAH9uX5fWUBIABOcg1Uzz60w2%2BLsfxLIyUT0xtk5ZojVKVdHErG6jX2zoUDJ7FAE7ZRDS21EECAg4S0kDDJd%2BsGy%2BEQ9dWIM0OWlTZuw5Bat25WP7nyo5ZzM7noIVaTwZ28he7jS4dxm29uP5YIszJMkXSeNYitHlqYpsyXqLOJv2JHacj&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=ASIA367HIG656THP6ONY%2F20250212%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20250212T114433Z&X-Amz-Expires=43200&X-Amz-SignedHeaders=host&X-Amz-Signature=f84df5697be3ef75a55e83c02ea9b7eea752a3a5276bf438316e089c626b6378"
    echo "Downloading from $DOWNLOAD_URL"

    # if ! curl --head -s -L "$DOWNLOAD_URL" | grep -q "HTTP/2 200"; then
    #     echo "File does not exist. Something has gone wrong"
    #     exit 1
    # fi
    mkdir -p "$TMP_DIR"
    curl -L "$DOWNLOAD_URL" -o "$TAR_FILE"

    echo "Download completed and saved to $TAR_FILE"

    mkdir -p "$EXTRACT_DIR"
    echo "Extracting $TAR_FILE to $EXTRACT_DIR"
    tar -xzvf "$TAR_FILE" -C "$EXTRACT_DIR" || { echo "Extraction failed!"; exit 1; }
    echo "Extraction complete. Files are in $EXTRACT_DIR"
}

move_to_bin_and_make_executable() {
    # Find the actual binary (ignoring macOS metadata)
    OTEL_BINARY_FILE=$(find "$EXTRACT_DIR" -type f -executable -name "otelcontrib*" | head -n 1)

    if [[ -z "$OTEL_BINARY_FILE" ]]; then
        echo "Error: No executable file found in $EXTRACT_DIR!"
        exit 1
    fi

    echo "Moving $OTEL_BINARY_FILE to $INSTALL_DIR..."
    sudo mv "$OTEL_BINARY_FILE" "$INSTALL_DIR/" || { echo "Move failed!"; exit 1; }

    # Ensure the binary is executable
    BIN_NAME=$(basename "$OTEL_BINARY_FILE")
    sudo chmod +x "$INSTALL_DIR/$BIN_NAME"

    EDGE_BINARY_FILE=$(find "$EXTRACT_DIR" -type f -executable -name "edge_*" | head -n 1)

    if [[ -z "$EDGE_BINARY_FILE" ]]; then
        echo "Error: No executable file found in $EXTRACT_DIR!"
        exit 1
    fi

    echo "Moving $EDGE_BINARY_FILE to $INSTALL_DIR..."
    sudo mv "$EDGE_BINARY_FILE" "$INSTALL_DIR/" || { echo "Move failed!"; exit 1; }

    # Ensure the binary is executable
    BIN_NAME=$(basename "$EDGE_BINARY_FILE")
    sudo chmod +x "$INSTALL_DIR/$BIN_NAME"

    echo "deleting $EXTRACT_DIR"
    rm -rf $EXTRACT_DIR

}

start_server() {
    echo "starting server"
    EDGE_BINARY_FILE=$(find "$INSTALL_DIR" -type f -executable -name "edge_*" | head -n 1)

    if [[ -z "$EDGE_BINARY_FILE" ]]; then
        echo "Error: No executable file found in $INSTALL_DIR!"
        exit 1
    fi
    echo "nohup \"$EDGE_BINARY_FILE\" > output.log 2>&1 &"
    nohup "$EDGE_BINARY_FILE" > output.log 2>&1 &
    sleep 5  # Give some time to start
    ps aux | grep "$(basename "$EDGE_BINARY_FILE")" | grep -v grep
}


# 1. check and parse environment variable
if ! parse_environment_variable "$@"; then exit 1; fi # Check if parsing was successful.

#2. check for dependencies needed are present. install if missing
dependencies_check

#3. identify arch
detect_system

#4. decode and extract config from base64 encoded token.
#   store  the config at $CONFIG_FILE location
decode_and_extract_config

#5. construct the download url required for the system and download the tar
#   extract binary at $TMP_DIR
download_and_extract_agent

#6. move the binary to $INSTALL_DIR and give execution permissions
move_to_bin_and_make_executable

#7. Start server
start_server

#TODO
# 1. systemctl / initd for restart management
