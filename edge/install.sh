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


PREREQS="sudo curl jq sha1sum"
INSTALL_DIR="/opt/observo"
TMP_DIR="/tmp/observo"
CONFIG_DIR="/opt/observo"
TAR_FILE="$TMP_DIR"/edge.tar.gz
EXTRACT_DIR="$CONFIG_DIR/binaries_edge"
PACKAGE_NAME="otelcol-contrib"
CONFIG_FILE="$CONFIG_DIR"/edge-config.json
BASE_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"
SERVICE_NAME="observo-agent"
LOG_DIR="/var/log/observo"
USER="observo"

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
    else
        echo "Error: install_id not found in argument"
        return 1 # Failure
    fi

    # Correct the regular expression to capture only the value after download_url=
    if [[ "$env_var" =~ download_url=([^\ ]+) ]]; then
        DOWNLOAD_URL="${BASH_REMATCH[1]}"  # Extract the full presigned URL
        echo "Extracted download_url: $DOWNLOAD_URL"

        export DOWNLOAD_URL  # Make it available to other functions
    else
        echo "Error: download_url not found in argument"
        return 1  # Failure
    fi

    return 0 # Success
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

    # Generate AGENT_ID from machine ID
    echo "Generating AGENT_ID from machine ID..."
    MachineId=$(cat /etc/machine-id 2>/dev/null || cat /var/lib/dbus/machine-id 2>/dev/null)
    HostName=$(hostname)

    if [ -z "$MachineId" ]; then
        echo "Error: Could not read machine ID"
        exit 1
    fi

    # Create composite string and generate proper UUID format
    COMPOSITE_STRING="${MachineId}:${HostName}:${ARCH}"
    echo "Composite string: $COMPOSITE_STRING"

    # Generate SHA1 hash and format as proper UUID (8-4-4-4-12 format)
    AGENT_ID=$(echo -n "$COMPOSITE_STRING" | sha1sum | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\).*/\1-\2-\3-\4-\5/')

    echo "Machine ID: $MachineId"
    echo "AGENT_ID (UUID): $AGENT_ID"

    # Export AGENT_ID for use in other functions
    export AGENT_ID
}


download_and_extract_agent() {
    PACKAGE="${PACKAGE_NAME}_${VERSION}_${OS}_${ARCH}.tar.gz"

    #TODO: remove this and point to our repo
    # DOWNLOAD_URL="${BASE_URL}/v${VERSION}/${PACKAGE}"
    echo "Downloading from $DOWNLOAD_URL"

    # Check if the URL is accessible (presigned URL might be expired)
    #if ! curl -s -L -I "$DOWNLOAD_URL" | grep -q "^HTTP/[12] 2"; then
    #    echo "Error: Download URL is not accessible. URL may have expired."
    #    exit 1
    #fi

    mkdir -p "$TMP_DIR"
    curl -L -# "$DOWNLOAD_URL" -o "$TAR_FILE"

    if [[ ! -f "$TAR_FILE" ]]; then
        echo "Error: Downloaded file not found at $TAR_FILE. URL may have expired or download failed."
        exit 1
    fi
    
    # if the url is expired then it make smaller file size. Check if file size is suspiciously small (likely an error response)
    FILE_SIZE=$(stat -f%z "$TAR_FILE" 2>/dev/null || stat -c%s "$TAR_FILE" 2>/dev/null || echo "0")
    MIN_EXPECTED_SIZE=10240  # 10KB minimum for a valid tar.gz archive
    
    if [[ $FILE_SIZE -lt $MIN_EXPECTED_SIZE ]]; then
        echo "Error: Downloaded file is too small ($FILE_SIZE bytes). Expected at least $MIN_EXPECTED_SIZE bytes."
        echo "This usually means the download URL has expired or returned an error response."
        echo "File contents (first 200 chars):"
        head -c 200 "$TAR_FILE" 2>/dev/null || cat "$TAR_FILE" | head -c 200
        echo ""
        exit 1
    fi
    
    echo "Download completed and saved to $TAR_FILE (size: $FILE_SIZE bytes)"

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

    # Fix ownership of the entire install directory after moving files
    echo "Setting ownership of $INSTALL_DIR to $USER:$USER"
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"

    # Ensure proper permissions for the directory and config file
    sudo chmod 755 "$INSTALL_DIR"
    if [[ -f "$CONFIG_FILE" ]]; then
        sudo chmod 644 "$CONFIG_FILE"
    fi

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

create_system_user() {
    echo "Creating system user and group: $USER"
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)
	    echo "Linux"
            if command -v useradd &>/dev/null; then
                if ! getent group "$USER" > /dev/null; then
                    echo "Creating group '$USER'..."
                    groupadd --system "$USER" || echo "Group creation failed"
                fi

                if ! id "$USER" &>/dev/null; then
                    echo "Creating system user '$USER'..."
                    useradd --system --no-create-home --shell /usr/sbin/nologin --gid "$USER" "$USER" || echo "User creation failed"
                fi

            elif command -v adduser &>/dev/null; then
                if ! getent group "$USER" > /dev/null; then
                    sudo addgroup -S "$USER"
                fi

                if ! id "$USER" &>/dev/null; then
                    adduser -S -H -s /sbin/nologin -G "$USER" "$USER"
                fi
            fi
            ;;
        Darwin*)
            echo "macOS detected. Please create user manually or handle via launchd if needed."
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "Windows detected. User creation not supported in this script."
            ;;
        *)
            echo "Unsupported OS. Please create user manually."
            exit 1
            ;;
    esac
}

setup_log_directory() {
    echo "Setting up log directory: $LOG_DIR"

    if [ ! -d "$LOG_DIR" ]; then
        echo "Creating log directory..."
        sudo mkdir -p "$LOG_DIR" || { echo "Failed to create log directory"; exit 1; }
    else
        echo "Log directory already exists."
    fi

    echo "Setting ownership to $USER:$USER"
    sudo chown "$USER:$USER" "$LOG_DIR" || { echo "Failed to set ownership on log directory"; exit 1; }
}

create_systemd_service() {
    echo "Setting up systemd service for Observo Edge..."

    unameOut="$(uname -s)"
    if [[ "$unameOut" != "Linux" ]]; then
        echo "Systemd setup is only supported on Linux. Detected OS: $(uname -s)"
        return
    fi

    EDGE_BINARY="$INSTALL_DIR/edge"

    if [[ ! -f "$EDGE_BINARY" ]]; then
        echo "Error: $EDGE_BINARY not found!"
        exit 1
    fi
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    echo "Creating systemd service file: $SERVICE_FILE"
    tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Observo Agent Service
After=network.target

[Service]
Type=simple
ExecStart=$EDGE_BINARY
Restart=always
RestartSec=5
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR

Environment="AGENT_ID=$AGENT_ID"
Environment="SITE_ID=$SITE_ID"
Environment="AUTH_TOKEN=$AUTH_TOKEN"
Environment="AGENT_VERSION=$AGENT_VERSION"
Environment="CONFIG_VERSION_ID=$CONFIG_VERSION_ID"
Environment="FLEET_ID=$FLEET_ID"
Environment="PLATFORM=$PLATFORM"
Environment="EDGE_MANAGER_URL=$EDGE_MANAGER_URL"
Environment="OTEL_LOG_FILE_PATH=$LOG_DIR/otel-collector.log"




StandardOutput=append:$LOG_DIR/observo-agent.log
StandardError=append:$LOG_DIR/observo-agent.log

[Install]
WantedBy=multi-user.target
EOF
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reexec || echo "daemon-reexec failed"
    sudo systemctl daemon-reload || echo "daemon-reload failed"

    echo "Enabling and starting $SERVICE_NAME..."
    sudo systemctl enable "$SERVICE_NAME" || echo "Enable failed"
    sudo systemctl restart "$SERVICE_NAME" || echo "Restart failed"
}

echo "$OBSERVO_HEADING"

#1 create user and group
create_system_user

#2 setup log directory
setup_log_directory

#3 check and parse environment variable
if ! parse_environment_variable "$@"; then exit 1; fi # Check if parsing was successful.

#4. check for dependencies needed are present. install if missing
dependencies_check

#5. identify arch
detect_system

#6. decode and extract config from base64 encoded token.
#   store  the config at $CONFIG_FILE location
decode_and_extract_config

#7. construct the download url required for the system and download the tar
#   extract binary at $TMP_DIR
download_and_extract_agent

#8. move the binary to $INSTALL_DIR and give execution permissions
move_to_bin_and_make_executable

#9 create systemd service
create_systemd_service