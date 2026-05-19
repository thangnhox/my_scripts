# termux_emulator.sh

A setup script that spins up an Android emulator in Docker and installs [Termux](https://termux.dev) on it, giving you a full Linux environment on Android — locally or over SSH.

## What It Does

1. **Starts an Android emulator** (API 30, x86_64) as a Docker container
2. **Connects ADB** to the emulator, with automatic SSH tunnel support for remote Docker hosts
3. **Installs Termux** (downloads the APK from GitHub if not already present)
4. **Initializes the Termux filesystem** by launching the app and waiting for bootstrap extraction
5. **Drops you into an ADB shell** with instructions to enter a full Termux session

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker | With access to `/dev/kvm` for hardware acceleration |
| ADB (Android Debug Bridge) | Must be installed; `~/.android/adbkey` must exist |
| `curl` | Used to download the Termux APK if not cached locally |
| ~4 GB free RAM | The emulator container is configured to use up to 4 GB |
| Linux host | KVM acceleration requires a Linux kernel |

## Usage

```bash
# Basic usage (downloads Termux APK automatically)
./termux_emulator.sh

# Provide a pre-downloaded APK to skip the download step
./termux_emulator.sh /path/to/termux-debug.apk
```

### Default APK path

If no argument is given, the script looks for the APK at:
```
$TMPDIR/apk/termux-debug.apk
```
If not found there, it downloads from the GitHub release:
```
https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_universal.apk
```

## Remote Docker Hosts (SSH)

If your `DOCKER_HOST` (or active Docker context) points to an SSH remote (e.g. `ssh://user@host`), the script automatically:

- Detects the SSH context
- Opens a local SSH tunnel on port `5555` to reach the emulator
- Connects ADB through the tunnel
- Cleans up the tunnel on exit

No manual configuration is needed.

## Logging into Termux

After installation, the script opens a standard ADB shell and prints the command needed to enter Termux. Copy and paste it:

```bash
run-as com.termux files/usr/bin/bash -lic \
  'export PREFIX=/data/data/com.termux/files/usr; \
   export PATH=/data/data/com.termux/files/usr/bin:$PATH; \
   export LD_PRELOAD=/data/data/com.termux/files/usr/lib/libtermux-exec.so; \
   export HOME=/data/data/com.termux/files/home; \
   bash -i'
```

> **Why not enter Termux directly?**  
> Running a nested interactive shell via `adb shell` causes "No job control in this shell" errors. Using `run-as` from within the ADB shell avoids this.

## Memory Warning

If the Docker host has less than **4 GB of available RAM**, the script will warn you and ask for confirmation before proceeding. Running below this threshold risks the container being OOM-killed.

## Docker Container Details

| Setting | Value |
|---|---|
| Container name | `android-emulator` |
| Image | `us-docker.pkg.dev/android-emulator-268719/images/30-google-x64:30.1.2` |
| Memory reservation | 2 GB |
| Memory limit | 4 GB |
| Memory + swap limit | 6 GB |
| ADB port | `5555` |

If a container named `android-emulator` already exists, the script starts it rather than creating a new one.

## Troubleshooting

**`~/.android/adbkey not found`**  
Run `adb start-server` once to generate ADB keys, or install ADB and connect to any device to trigger key generation.

**Container OOM-killed**  
Free up RAM on the host or increase swap. The emulator is memory-intensive.

**`/dev/kvm` not available**  
KVM must be enabled in your host's BIOS/UEFI and supported by the kernel. Without it, the emulator will either fail to start or run too slowly to be usable.

**Termux bootstrap takes too long**  
The script waits 15 seconds for Termux's first-launch bootstrap extraction. On slow storage or heavily loaded hosts you may need to wait longer before pasting the login command.

