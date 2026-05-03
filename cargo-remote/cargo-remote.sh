#!/usr/bin/env bash
set -e

TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
mkdir -p "$TMPDIR"
export TMPDIR

# Cargo passes the subcommand name as the first argument.
# If invoked as `cargo remote run`, $1 is "remote". We remove it.
if [ "$1" = "remote" ]; then
    shift
fi

# Intercept the help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ -z "$1" ]; then
    echo "cargo-remote"
    echo "A transparent wrapper to execute Cargo commands on a remote Docker daemon."
    exit 0
fi

CONTAINER="rust-tmp-$(basename "$PWD")"
IMAGE="rust:latest"
WORKDIR="/workspace"

CARGO_REGISTRY_VOL="cargo-registry-cache"
CARGO_GIT_VOL="cargo-git-cache"

# Guarantee cleanup even if you hit Ctrl+C or the script crashes
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1' EXIT

# Create the container using explicit --mount syntax
docker create \
  --name "$CONTAINER" \
  --mount type=volume,source="$CARGO_REGISTRY_VOL",target="/usr/local/cargo/registry" \
  --mount type=volume,source="$CARGO_GIT_VOL",target="/usr/local/cargo/git" \
  --workdir "$WORKDIR" \
  "$IMAGE" \
  sleep infinity >/dev/null

docker start "$CONTAINER" >/dev/null

# Sync files to the container
docker exec "$CONTAINER" mkdir -p "$WORKDIR"
docker cp "." "$CONTAINER:$WORKDIR/"

# Execute the command
docker exec -it --workdir "$WORKDIR" "$CONTAINER" cargo "$@"
