#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Variable for the Termux APK (pass as argument 1, or defaults to local file)
TERMUX_APK=${1:-"$TMPDIR/apk/termux-debug.apk"}
TERMUX_APK_URL="https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_universal.apk"

echo "=== Android Emulator & Termux Setup ==="

# Ensure ADB server is running and keys are generated
adb start-server
if [ ! -f ~/.android/adbkey ]; then
    echo "Error: ~/.android/adbkey not found. Please ensure adb is properly installed."
    exit 1
fi

# Context detection: Unix vs SSH
# We detect this early to use it for both RAM checks and ADB tunneling.
DOCKER_ENDPOINT=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "unix://")}
SSH_TARGET=""
if [[ "$DOCKER_ENDPOINT" == ssh://* ]]; then
    SSH_TARGET="${DOCKER_ENDPOINT#ssh://}"
fi

# Check Docker Host RAM (Available memory)
echo "Checking Docker host available memory..."
HOST_MEM_MB=""
if [ -n "$SSH_TARGET" ]; then
    # Fetch available memory from remote SSH host
    HOST_MEM_MB=$(ssh "$SSH_TARGET" "awk '/MemAvailable/ {print int(\$2/1024)}' /proc/meminfo" 2>/dev/null || true)
elif [ -f /proc/meminfo ]; then
    # Fetch available memory from local Linux host
    HOST_MEM_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || true)
fi

if [ -z "$HOST_MEM_MB" ]; then
    echo "Note: Could not determine available memory natively. Falling back to total memory."
    if ! HOST_MEM_BYTES=$(docker info -f '{{.MemTotal}}' 2>/dev/null); then
        echo "Error: Could not retrieve Docker info. Is the Docker daemon running and accessible?"
        exit 1
    fi
    HOST_MEM_MB=$(echo "$HOST_MEM_BYTES" | awk '{print int($1/1024/1024)}')
fi

if [ "$HOST_MEM_MB" -lt 4000 ]; then
    echo "WARNING: Docker host has only ~${HOST_MEM_MB}MB of available (or total) RAM."
    echo "The Android emulator container is configured to use up to 4GB of RAM."
    echo "This may cause system instability or the container to be OOM killed."
    read -p "Do you want to continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 1
    fi
else
    echo "Docker host memory: ~${HOST_MEM_MB}MB available (Sufficient)"
fi

# 1. Start emulator
echo "[1/5] Starting Android Emulator via Docker..."
# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -Eq "^android-emulator\$"; then
    # Added -d to run in detached mode so the script can continue
    docker run -d --name android-emulator \
        --memory-reservation "2g" \
        --memory "4g" \
        --memory-swap "6g" \
        -e ADBKEY="$(cat ~/.android/adbkey)" \
        --device /dev/kvm \
        us-docker.pkg.dev/android-emulator-268719/images/30-google-x64:30.1.2
else
    echo "Container 'android-emulator' already exists. Ensuring it's started..."
    docker start android-emulator
fi

# Get container IP and connect ADB
echo "Fetching container IP address..."
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' android-emulator)

if [ -n "$SSH_TARGET" ]; then
    echo "SSH context detected ($SSH_TARGET). Creating SSH tunnel..."
    LOCAL_PORT=5555
    
    # Start SSH tunnel in the background
    ssh -N -L ${LOCAL_PORT}:${CONTAINER_IP}:5555 "$SSH_TARGET" &
    SSH_TUNNEL_PID=$!
    
    # Ensure the tunnel is cleanly closed when the script exits
    trap 'echo -e "\nCleaning up SSH tunnel..."; kill $SSH_TUNNEL_PID 2>/dev/null || true' EXIT
    
    ADB_TARGET="localhost:${LOCAL_PORT}"
    echo "Connecting to emulator via SSH tunnel at $ADB_TARGET..."
    sleep 2 # Give the tunnel a moment to establish
else
    echo "Unix context detected."
    ADB_TARGET="$CONTAINER_IP:5555"
    echo "Connecting to emulator at $ADB_TARGET..."
fi

sleep 5 # Give the container a brief moment to initialize network ports
adb connect "$ADB_TARGET"

# 2. Wait for emulator to fully boot
echo "[2/5] Waiting for emulator to boot (this may take a few minutes)..."
adb -s "$ADB_TARGET" wait-for-device
while [ "$(adb -s "$ADB_TARGET" shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; do
    sleep 2
done
echo "Emulator is ready!"

# 3. Install Termux debuggable from Github
echo "[3/5] Installing Termux..."

# Check if Termux is already installed
if adb -s "$ADB_TARGET" shell pm list packages com.termux | grep -q "com.termux"; then
    echo "Termux is already installed on the emulator. Skipping download and installation."
else
    # Download APK if it doesn't exist locally
    if [ ! -f "$TERMUX_APK" ]; then
        echo "Termux APK not found locally at '$TERMUX_APK'."
        echo "Downloading from GitHub release..."
        mkdir -p "$(dirname "$TERMUX_APK")"
        curl -L --progress-bar -o "$TERMUX_APK" "$TERMUX_APK_URL"
    fi

    if [ -f "$TERMUX_APK" ]; then
        # -t allows installation of test (debuggable) APKs, -r replaces existing application
        echo "Installing $TERMUX_APK onto emulator..."
        adb -s "$ADB_TARGET" install -r -t "$TERMUX_APK"
    else
        echo "Error: Failed to find or download Termux APK."
        exit 1
    fi
fi

# 4. Init termux filesystem
echo "[4/5] Initializing Termux filesystem..."
adb -s "$ADB_TARGET" shell am start -n com.termux/.app.TermuxActivity

# Wait a moment for Termux to extract its bootstrap packages on first launch
echo "Waiting 15 seconds for bootstrap extraction..."
sleep 15

# 5. Login into termux
echo "[5/5] Preparing to log into Termux..."
echo "------------------------------------------------------"
echo "To avoid 'No job control in this shell' errors, you will now enter the standard ADB shell."
echo "Once inside, COPY AND PASTE the following command to enter Termux:"
echo ""
echo "run-as com.termux files/usr/bin/bash -lic 'export PREFIX=/data/data/com.termux/files/usr; export PATH=/data/data/com.termux/files/usr/bin:\$PATH; export LD_PRELOAD=/data/data/com.termux/files/usr/lib/libtermux-exec.so; export HOME=/data/data/com.termux/files/home; bash -i'"
echo ""
echo "------------------------------------------------------"
adb -s "$ADB_TARGET" shell

