#!/bin/bash

OBSERVO_HEADING="
       #######    ######      #####     #######    ######     #     #    #######              #       ###                      
       #     #    #     #    #     #    #          #     #    #     #    #     #             # #       #                       
       #     #    #     #    #          #          #     #    #     #    #     #            #   #      #                       
       #     #    ######      #####     #####      ######     #     #    #     #           #     #     #                       
       #     #    #     #          #    #          #   #       #   #     #     #    ###    #######     #                       
       #     #    #     #    #     #    #          #    #       # #      #     #    ###    #     #     #                       
       #######    ######      #####     #######    #     #       #       #######    ###    #     #    ###                      
                                                                                                                               
                                                                                                                               
                                                                                                                               
                                                                                                                               
 ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### 
                                                                                                                               
                                                                                                                               
                                                                                                                               
                                                                                                                               
 ####### ######   #####  #######    ### #     #  #####  #######    #    #       #          #    ####### ### ####### #     #    
 #       #     # #     # #           #  ##    # #     #    #      # #   #       #         # #      #     #  #     # ##    #    
 #       #     # #       #           #  # #   # #          #     #   #  #       #        #   #     #     #  #     # # #   #    
 #####   #     # #  #### #####       #  #  #  #  #####     #    #     # #       #       #     #    #     #  #     # #  #  #    
 #       #     # #     # #           #  #   # #       #    #    ####### #       #       #######    #     #  #     # #   # #    
 #       #     # #     # #           #  #    ## #     #    #    #     # #       #       #     #    #     #  #     # #    ##    
 ####### ######   #####  #######    ### #     #  #####     #    #     # ####### ####### #     #    #    ### ####### #     #    
                                                                                                                               
"


PREREQS="sudo curl jq"
INSTALL_DIR="/opt/observo"
TMP_DIR="/tmp/observo"
CONFIG_DIR="/opt/observo"
TAR_FILE="$TMP_DIR"/edge.tar.gz
EXTRACT_DIR="$CONFIG_DIR/binaries_edge"
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
    DOWNLOAD_URL="https://observo-service-images.s3.us-east-1.amazonaws.com/edge-binaries/linux_amd64.tar.gz?response-content-disposition=inline&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEJX%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIEDdHQVY%2BbrYyFCTRZslyH17dBDLlhBXx3WyViDoVKXGAiA%2BnDq8RZzdN7CPGVNGzCwODpA2MOUtSv%2ByJeHijK9RrirrAwi%2B%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDgyMjQzNDM0NjkzOSIMfCxbd6dw3PDfo%2B5TKr8DvNPIrTGTs4c9MxcOA%2BWpVOjfm7MQ3xL74%2BYRfVNKxaPjYGxkQp5oPRzhgia655RFXsWapKV5qR%2BSEgAH83RCnUT3KBJIdidkaJUEwWi4f2PmrOdSTJMHAPwmkZaOmvfduqA2o%2FgSW963pI46HL0srfmrlgKFw65QczI8PabbDw361uoHD8katmOtLIjH59uVXXtT0RPE9SVLKfhnlpgDVcS9VRH%2FyaS%2Bu5vM8FJDfwgRw%2FD5jw7Tnv2woNgRKqIOzlyfMJ0BB4NRKzPeUG51CCX2NDvj1w6MG1urqLp5u0wqxspiLJ7fq8TENfCkatgp8lFUydqKLiqZCvRQlnrwL%2FkmPwaYWlk4ZJBdBsZIxONCDoBLso1kKLFgnL7JlvRZSy7ttJfonRKDuA2St36EBy915zOFr42layTQdLQXRTpbX0U1g1rJHMYs%2FEhh%2Fk%2Bx9VdGbuXPvsMUiWDeOH9OEVmSX8MQ4Mv86M2DcvJ64V6lvVgd46ldIqFfZFk8qO%2BkvaZW4SBIVEHukcqNMNP1KzAFgMTkZvBhivjt8Bh08evXvdaqtPetSliI8Rg%2FbI%2F38T222%2Bj3t%2FOlsADTQOe3MLG93L0GOuUCoVWlj%2BNgKJeXMvAJ2PJWsMls3KcmPrfWKjPSrdQOgWtafsMvtfc79DamSqtXaKdvFBOwHu8r0%2BS10j8CPka%2FWPFRfAlumGzdruDLfia5xhH8evVBstHdGisViRQJjuGZs6MuRimSV9s%2B%2FTgDnqDaWc44ioEfAuzXFX%2FG52pVZo0THhlcy8iOcs74LEX1gMFooWbZLUbvNYguwELXcBtBsaVk0GcAGQ8KsGUzJkkL2y5XjdKibIi%2B7Cck5nZnGlmClt5VkMtq%2BggVGmhkHYuVgvo11%2FLFGrFoo%2Fj8OBuJgEHXSrMqwy1DkFdSfbj7jklPxwNN1jEQZ5CD22rDU6ssRgIkuI%2Blu3egDtLrVxGJrxXZIajXiFEkEhkfVi15Q5%2FPxAZx4LKiIP8Sjcr1ZLsnyHTuFjx2gNaaAFC%2B5Kjtlp1v5SZN3t7FnCgvDT%2BBTt6ze5frHY00oU%2FUL1ylAbze7PZXrlmp&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=ASIA367HIG65QWGD4DRE%2F20250220%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20250220T124121Z&X-Amz-Expires=43200&X-Amz-SignedHeaders=host&X-Amz-Signature=21884220ce147182c8009aea2cc4721e44c926f23628fa5f2dbbb426019b6bbf"
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

    EDGE_BINARY_FILE=$(find "$EXTRACT_DIR" -type f -executable -name "edge*" | head -n 1)

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
    rm -rf $TMP_DIR

}

start_server() {
    echo "starting server"
    EDGE_BINARY_FILE=$(find "$INSTALL_DIR" -type f -executable -name "edge" | head -n 1)
    echo "$EDGE_BINARY_FILE"

    if [[ -z "$EDGE_BINARY_FILE" ]]; then
        echo "Error: No executable file found in $INSTALL_DIR!"
        exit 1
    fi
    echo "nohup $EDGE_BINARY_FILE > $INSTALL_DIR/output.log 2>&1 &"
    nohup "$EDGE_BINARY_FILE" > "$INSTALL_DIR/edge_output.log" 2>&1 &
    echo $! > "$INSTALL_DIR/edge.pid"
    echo "Observo Edge started with PID $(cat "$INSTALL_DIR/edge.pid")"
}


echo "$OBSERVO_HEADING"

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
