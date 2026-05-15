#!/usr/bin/env bash
set -e

# Intercept the help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ -z "$1" ]; then
    echo "node-remote"
    echo "A transparent wrapper to execute node/npm commands on a remote Docker daemon."
    echo "Designed for environments without a local dockerd (e.g., Android/Termux)."
    echo ""
    echo "Usage: node-remote [--tunnel <port>] [--public] [command...]"
    echo "Examples:"
    echo "  node-remote --tunnel 3000 npm run dev"
    echo "  node-remote node index.js"
    echo "  node-remote bash -c \"npm install && node index.js\""
    exit 0
fi

# If invoked as something like `npm remote install`, $1 is "remote". We remove it.
if [ "$1" = "remote" ]; then
    shift
fi

# Parse wrapper flags
TUNNEL_PORT=""
BIND_ADDR="127.0.0.1"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -t|--tunnel)
            TUNNEL_PORT="$2"
            shift 2
            ;;
        --public)
            BIND_ADDR="0.0.0.0"
            shift
            ;;
        *)
            # Stop parsing at the first non-wrapper flag (these are passed to the container)
            break
            ;;
    esac
done

# Append PID to prevent collisions during concurrent runs
CONTAINER="node-tmp-$(basename "$PWD")-$$"
IMAGE="node:latest"
WORKDIR="/workspace"
NPM_CACHE_VOL="npm-cache"

SSH_PID=""

# Guarantee cleanup even if you hit Ctrl+C or the script crashes
cleanup() {
    echo "Signal received. Exiting ..."

    # 1. Kill the background SSH tunnel if we started one
    if [ -n "$SSH_PID" ]; then
        kill "$SSH_PID" 2>/dev/null || true
    fi

    # 2. Remove the remote container
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker rm -f "$CONTAINER" >/dev/null 2>&1
    fi
}

# Bind the cleanup function to the EXIT signal
trap cleanup EXIT

# Create the container
docker create \
  --name "$CONTAINER" \
  --mount type=volume,source="$NPM_CACHE_VOL",target="/root/.npm" \
  --memory-reservation "256m" \
  --memory "512m" \
  --memory-swap "1g" \
  --workdir "$WORKDIR" \
  "$IMAGE" \
  sleep infinity >/dev/null

docker start "$CONTAINER" >/dev/null

# Automatically setup SSH Tunnel if requested
if [ -n "$TUNNEL_PORT" ]; then
    # Grab the internal IP address of the container on the remote host
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER")
    
    # Get the active Docker endpoint (resolves 'docker context' like your 'experiment' setup)
    DOCKER_ENDPOINT=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "$DOCKER_HOST")
    
    # Check if the endpoint is an SSH connection
    if [[ "$DOCKER_ENDPOINT" == ssh://* ]]; then
        echo "=> Auto-tunneling ${BIND_ADDR}:$TUNNEL_PORT to $CONTAINER_IP:$TUNNEL_PORT..."
        
        # Start the SSH tunnel in the background using the specified bind address
        ssh -N -L "${BIND_ADDR}:${TUNNEL_PORT}:${CONTAINER_IP}:${TUNNEL_PORT}" "$DOCKER_ENDPOINT" &
        SSH_PID=$!
    else
        echo "=> Warning: --tunnel flag requires an ssh:// Docker context or DOCKER_HOST."
        echo "=> Current endpoint is: $DOCKER_ENDPOINT"
        echo "=> Could not automatically create the SSH tunnel."
    fi
fi

# Sync local files up to the remote container
docker exec "$CONTAINER" mkdir -p "$WORKDIR"
docker cp "." "$CONTAINER:$WORKDIR/"

# Execute the generic command
docker exec -it --workdir "$WORKDIR" "$CONTAINER" "$@"
