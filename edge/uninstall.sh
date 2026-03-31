#!/bin/bash

INSTALL_DIR="/opt/observo"
CONFIG_FILE="$INSTALL_DIR/edge-config.json"
LOG_DIR="/var/log/observo"
SERVICE_NAME="observo-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OBSERVO_USER="observo"

KEEP_CONFIG=false
KEEP_LOGS=false
KEEP_USER=false

usage() {
    echo "Usage: $0 [--keep-config] [--keep-logs] [--keep-user]"
    echo "  --keep-config  Preserve edge-config.json (use during upgrade)"
    echo "  --keep-logs    Preserve /var/log/observo (use during upgrade)"
    echo "  --keep-user    Preserve observo system user/group (use during upgrade, Linux only)"
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --keep-config) KEEP_CONFIG=true ;;
        --keep-logs)   KEEP_LOGS=true ;;
        --keep-user)   KEEP_USER=true ;;
        *) echo "Unknown argument: $arg"; usage ;;
    esac
done

OS="$(uname -s)"
echo "Uninstalling Observo Edge on $OS..."

# Step 1: Stop service / kill process
if [[ "$OS" == "Linux" ]]; then
    echo "Stopping systemd service: $SERVICE_NAME..."
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo "Error: Service file $SERVICE_FILE not found."
        exit 1
    fi
    sudo systemctl stop "$SERVICE_NAME" || { echo "Error: Failed to stop service $SERVICE_NAME."; exit 1; }
    sudo systemctl disable "$SERVICE_NAME" || { echo "Error: Failed to disable service $SERVICE_NAME."; exit 1; }

    echo "Removing service file: $SERVICE_FILE..."
    sudo rm "$SERVICE_FILE" || { echo "Error: Failed to remove $SERVICE_FILE."; exit 1; }
    sudo systemctl daemon-reload || { echo "Error: Failed to reload systemd daemon."; exit 1; }

elif [[ "$OS" == "Darwin" ]]; then
    echo "Checking for running edge processes..."
    if pgrep -x "edge" > /dev/null 2>&1; then
        echo "Killing edge process..."
        sudo pkill -x "edge" || { echo "Error: Failed to kill edge process."; exit 1; }
        sleep 1
        if pgrep -x "edge" > /dev/null 2>&1; then
            sudo pkill -9 -x "edge" || { echo "Error: Failed to force kill edge process."; exit 1; }
        fi
    else
        echo "No running edge process found, continuing."
    fi
else
    echo "Error: Unsupported OS: $OS"
    exit 1
fi

# Step 2: Remove binaries
echo "Removing binaries from $INSTALL_DIR..."
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Error: Install directory $INSTALL_DIR not found."
    exit 1
fi

shopt -s nullglob
BINARIES=("$INSTALL_DIR"/edge "$INSTALL_DIR"/otelcontrib*)
shopt -u nullglob

if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "Error: No binaries found in $INSTALL_DIR."
    exit 1
fi

for f in "${BINARIES[@]}"; do
    echo "Removing $f..."
    sudo rm "$f" || { echo "Error: Failed to remove $f."; exit 1; }
done

# Remove runtime files left by the process (non-fatal if missing)
for f in "$INSTALL_DIR/edge.pid" "$INSTALL_DIR/edge_output.log" "$INSTALL_DIR/output.log"; do
    [[ -f "$f" ]] && sudo rm "$f"
done

# Step 3: Remove config
if [[ "$KEEP_CONFIG" == true ]]; then
    echo "Skipping config removal (--keep-config set)."
else
    echo "Removing config: $CONFIG_FILE..."
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Config file $CONFIG_FILE not found."
        exit 1
    fi
    sudo rm "$CONFIG_FILE" || { echo "Error: Failed to remove $CONFIG_FILE."; exit 1; }
fi

# Step 4: Remove install directory
# Keep it only if config is being preserved (config lives inside the dir).
if [[ "$KEEP_CONFIG" == true ]]; then
    echo "Preserving install directory (config retained): $INSTALL_DIR"
else
    echo "Removing install directory: $INSTALL_DIR..."
    sudo rm -rf "$INSTALL_DIR" || { echo "Error: Failed to remove $INSTALL_DIR."; exit 1; }
fi

# Step 5: Remove log directory
if [[ "$KEEP_LOGS" == true ]]; then
    echo "Skipping log directory removal (--keep-logs set)."
else
    echo "Removing log directory: $LOG_DIR..."
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "Error: Log directory $LOG_DIR not found."
        exit 1
    fi
    sudo rm -rf "$LOG_DIR" || { echo "Error: Failed to remove $LOG_DIR."; exit 1; }
fi

# Step 6: Remove system user and group (Linux only)
if [[ "$OS" == "Linux" ]]; then
    if [[ "$KEEP_USER" == true ]]; then
        echo "Skipping user removal (--keep-user set)."
    else
        echo "Removing system user: $OBSERVO_USER..."
        if ! id "$OBSERVO_USER" &>/dev/null; then
            echo "Error: User $OBSERVO_USER does not exist."
            exit 1
        fi
        sudo userdel "$OBSERVO_USER" || { echo "Error: Failed to remove user $OBSERVO_USER."; exit 1; }

        # userdel may have already removed the primary group; only error if it still exists and we can't remove it
        if getent group "$OBSERVO_USER" > /dev/null 2>&1; then
            echo "Removing system group: $OBSERVO_USER..."
            sudo groupdel "$OBSERVO_USER" || { echo "Error: Failed to remove group $OBSERVO_USER."; exit 1; }
        fi
    fi
fi

echo "Observo Edge uninstalled successfully."
