# ReapOBS

Lua ReaScript that synchronizes REAPER DAW and OBS Studio recording with a single action. Uses obs-websocket v5 via obs-cmd CLI. Built for Linux.

---

## Table of Contents

- [Overview](#overview)
- [Prior Art & Motivation](#prior-art--motivation)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [OBS Setup](#obs-setup)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Adding a Toolbar Button](#adding-a-toolbar-button)
- [Auto-Import Feature](#auto-import-feature)
- [Recommended Workflow](#recommended-workflow)
- [Synchronization Notes](#synchronization-notes)
- [Troubleshooting](#troubleshooting)
- [Audio Stack Notes](#audio-stack-notes)
- [Security Considerations](#security-considerations)
- [Uninstallation](#uninstallation)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Overview

ReapOBS synchronizes audio recording in REAPER DAW with video recording in OBS Studio. Press a single key or toolbar button in REAPER and both applications start recording simultaneously. Press it again to stop both at once.

Without ReapOBS, starting and stopping two separate applications manually is error-prone. A slightly delayed start or stop creates an audio/video offset that must be corrected in post-production  or worse, causes you to miss the beginning of a take. ReapOBS eliminates this by coordinating both applications from a single REAPER action.

The integration uses three independent Lua ReaScripts: one to start, one to stop, and one toggle script that is recommended for everyday use. Each script checks the current recording state, starts or stops the relevant application, and optionally drops a project marker in REAPER's timeline for reference during editing.

---

## Prior Art & Motivation

An existing open-source project **[leafac/reaper](https://github.com/leafac/reaper)** (MIT license) already includes REAPER-to-OBS recording sync scripts: Start, Stop, and Toggle recording. It's part of a larger collection of REAPER effects and scripts by Leandro Facchinetti, installable via ReaPack.

However, leafac's OBS scripts have a critical compatibility problem: they use his own Node.js-based obs-cli which only speaks the **obs-websocket v4 protocol**. Since OBS Studio 28 (released 2022), OBS ships with obs-websocket v5 built-in and v4 is no longer supported. This means leafac's scripts **do not work with any modern OBS version**. The [issue has been open since March 2023](https://github.com/leafac/reaper/issues/6) with no fix, and the project hasn't seen significant updates in years.

ReapOBS was created as a lightweight, focused alternative that:
- Uses **obs-cmd** by grigio (Rust binary, zero dependencies) which supports obs-websocket v5 natively
- Works with current OBS Studio versions out of the box
- Is Linux-only (Debian) by design
- Is a standalone project rather than part of a larger monorepo
- Has no Node.js or other runtime dependencies

---

## How It Works

```
REAPER (Lua ReaScript)
  
   reaper.Main_OnCommand(1013)  REAPER starts recording
  
   io.popen("obs-cmd recording start")
       
        WebSocket (localhost:4455)
            
             OBS Studio starts recording
```

**Components:**

- **Lua ReaScript**  REAPER's built-in scripting environment exposes `io.popen()` and `os.execute()` for shell access. The scripts use `io.popen()` so they can read the output of obs-cmd and check whether the command succeeded.
- **obs-cmd**  A standalone CLI tool written in Rust. It sends commands to OBS Studio over the WebSocket v5 protocol. Because it is a compiled binary, it has no runtime dependencies and executes in under 50 ms.
- **OBS Studio WebSocket v5**  OBS Studio 28+ includes obs-websocket v5 as a built-in feature. No additional plugin is required. You simply enable the WebSocket server in OBS settings.
- **Non-blocking execution**  `io.popen()` briefly pauses REAPER's UI thread while obs-cmd runs. Since obs-cmd completes in under 50 ms, this is imperceptible in practice.

---

## Requirements

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| REAPER | v6.0+ | Linux native build |
| OBS Studio | v28.0+ | obs-websocket v5 is built in |
| obs-cmd | latest | Installed by `install.sh` or manually |
| ffmpeg | latest | Required for robust auto-import fallback/conversion |
| Linux | Debian/Ubuntu | Tested on Debian with PipeWire audio |
| curl | any | Required for obs-cmd download |

---

## Installation

### Method 1: Automated (recommended)

```bash
git clone https://github.com/Zesseth/ReapOBS.git
cd ReapOBS
chmod +x install.sh
./install.sh
```

The installer will:
1. Check for REAPER, OBS Studio, and curl
2. Offer to download and install obs-cmd if it is not found
3. Copy the Lua scripts to `~/.config/REAPER/Scripts/ReapOBS/`
4. Print step-by-step instructions for loading the scripts in REAPER

### Method 2: Manual

**Step 1  Install obs-cmd:**

```bash
curl -fsSL https://github.com/grigio/obs-cmd/releases/latest/download/obs-cmd-x64-linux.tar.gz \
  | tar -xz
sudo mv obs-cmd /usr/local/bin/obs-cmd
sudo chmod +x /usr/local/bin/obs-cmd
obs-cmd --version
```

**Step 2  Copy the scripts:**

```bash
mkdir -p ~/.config/REAPER/Scripts/ReapOBS
cp scripts/*.lua ~/.config/REAPER/Scripts/ReapOBS/
```

**Step 3  Load scripts in REAPER:**

1. Open REAPER
2. Go to **Actions  Show Action List**
3. Click **New action...**  **Load ReaScript...**
4. Navigate to `~/.config/REAPER/Scripts/ReapOBS/`
5. Select and load all the `.lua` files
6. Assign keyboard shortcuts as desired (see [Usage](#usage))

---

## OBS Setup

1. Open **OBS Studio**
2. Go to **Tools  WebSocket Server Settings**
3. Check **Enable WebSocket Server**
4. Note the port number (default: **4455**)
5. Either set a password and add it to `OBS_WEBSOCKET_URL` in the scripts, or uncheck **Enable Authentication** for a passwordless connection
6. In **Settings -> Output -> Recording**, set **Recording Format = MP4**
7. Click **OK** and keep OBS running whenever you use ReapOBS

---

## Configuration

Configuration is now centralized in `reapobs_config.lua`. Open this file in a text editor to adjust settings for all scripts at once.

### Main Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `OBS_CMD_PATH` | `/usr/local/bin/obs-cmd` | Full path to the obs-cmd binary. Run `which obs-cmd` to find it. |
| `OBS_WEBSOCKET_URL` | `obsws://localhost:4455` | Connection URL. Format: `obsws://host:port` (no password) or `obsws://host:port/password`. |
| `ADD_MARKER_ON_START` | `true` | Add a REAPER project marker when recording starts. |
| `MARKER_PREFIX` | `"REC START"` | Text label for start markers. |
| `ADD_MARKER_ON_STOP` | `true` | Add a REAPER project marker when recording stops. |
| `STOP_MARKER_PREFIX` | `"REC STOP"` | Text label for stop markers. |
| `REQUIRE_OBS` | `true` | When `true`, REAPER recording will not start if OBS is unavailable. Set to `false` to record REAPER audio even without OBS. |
| `DEBUG` | `false` | Print status messages to the REAPER console. Enable for troubleshooting. Error dialogs (e.g., connection failures) always appear regardless of this setting. |

### Auto-Import Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTO_IMPORT_VIDEO` | `true` | Automatically imports the latest video file into REAPER after recording stops. |
| `FFMPEG_PATH` | `/usr/bin/ffmpeg` | Path to ffmpeg binary for video conversion. |
| `OBS_OUTPUT_DIR` | `/mnt/data/VideoRecording` | Directory where OBS saves recordings. Must be an absolute path and readable. |
| `DELETE_ORIGINAL` | `false` | Set to `true` to delete the original video file after importing to REAPER. |
| `VIDEO_EXTENSIONS` | `{ ".mp4" }` | Video file extensions to look for when auto-importing. Keep OBS recording format as MP4. |
| `RECENT_VIDEO_MINUTES` | `60` | Time window in minutes to consider a video file as "recent" for auto-import. |
| `VIDEOS_BUS_NAME` | `"Videos"` | Name of the track/folder to create for imported videos. |

**Example: passwordless local connection**
```lua
OBS_WEBSOCKET_URL = "obsws://localhost:4455"
```

**Example: connection with password**
```lua
OBS_WEBSOCKET_URL = "obsws://localhost:4455/mysecretpassword"
```

**Example: enable auto-import**
```lua
AUTO_IMPORT_VIDEO = true
OBS_OUTPUT_DIR = "/home/yourusername/Videos/obs_recordings"
VIDEO_EXTENSIONS = {".mp4"}
```

> **Important:** ReapOBS auto-import is validated for **MP4** recordings. In OBS, set Recording Format to MP4.

---

## Usage

Four scripts are provided. Load all scripts in REAPER's Action List (see [Installation](#installation)) and assign shortcuts as desired.

### 1. Toggle Recording  `reapobs_toggle_recording.lua` *(recommended)*

Checks whether REAPER is currently recording:
- **Not recording**  starts both REAPER and OBS
- **Recording**  stops both REAPER and OBS

This is the script to assign to a keyboard shortcut. **Recommended shortcut: `Shift+R`**

### 2. Start Recording  `reapobs_start_recording.lua`

- Verifies obs-cmd is installed and OBS is reachable
- If auto-import is enabled, verifies `OBS_OUTPUT_DIR` before starting
- Starts OBS recording via `obs-cmd recording start`
- Starts REAPER recording via Transport: Record (action 1013)
- Optionally adds a `REC START` marker to the REAPER timeline

### 3. Stop Recording  `reapobs_stop_recording.lua`

- Stops REAPER recording via Transport: Stop (action 1016)
- Optionally adds a `REC STOP` marker to the REAPER timeline
- Stops OBS recording via `obs-cmd recording stop`
- If auto-import is enabled, automatically imports the latest video file

### Adding a Toolbar Button

You can add a toolbar button in REAPER so you don't need to remember a keyboard shortcut:

1. Go to **Actions  Show Action List**
2. Find the ReapOBS script you want (e.g., `Script: reapobs_toggle_recording.lua`)
3. Right-click the action and select **Copy selected action command ID**
4. Close the Action List
5. Right-click on any **toolbar** and select **Customize toolbar...**
6. Click **Add...** and paste the command ID, or use the **Filter** to find the ReapOBS action
7. Select the action in the toolbar list, then click the icon area at the **bottom left** of the dialog
8. Filter for **"reapobs"** and select the ReapOBS icon
9. Click **OK** to save

Alternatively, you can create a completely new toolbar: **View  Toolbars  New toolbar...** and add the ReapOBS actions there.

ReapOBS includes a toolbar icon (`reapobs_toggle.png`) installed automatically by `install.sh` to `~/.config/REAPER/Data/toolbar_icons/`.

> **Tip:** REAPER can highlight the toolbar button when recording is active. Right-click the toolbar  **Customize toolbar...**, select the ReapOBS action, and check **Show button as enabled for toggleable actions**. This highlight is provided by REAPER; ReapOBS installs the single `reapobs_toggle.png` icon.

---

## Auto-Import Feature

The auto-import feature automatically imports the latest MP4 video file from your OBS output directory into REAPER after recording stops. This is especially useful for streamlining your workflow.

### How Auto-Import Works

1. On recording start, if auto-import is enabled, the script checks that `OBS_OUTPUT_DIR` exists and is readable
2. On stop, it searches `OBS_OUTPUT_DIR` for the most recently modified matching video file
3. It creates a "Videos" folder track in your REAPER project (if it doesn't exist)
4. It creates a child track under "Videos" and appends all later takes under the same folder
5. It aligns the imported item to the latest `REC START` marker position
6. It imports the video into the child track (with retries and ffmpeg fallback conversion when needed)
7. It keeps the original file in OBS output by default (`DELETE_ORIGINAL = false`)

### Auto-Import Configuration

Auto-import is enabled by default (`AUTO_IMPORT_VIDEO = true`) in `reapobs_config.lua`. Configure the following settings:

- `OBS_OUTPUT_DIR`: The directory where OBS saves its recordings
- `FFMPEG_PATH`: Path to ffmpeg for video conversion (if needed)
- `VIDEO_EXTENSIONS`: File extensions to look for (`.mp4` recommended/validated)
- `RECENT_VIDEO_MINUTES`: How recent a file must be to be considered
- `VIDEOS_BUS_NAME`: Name of the parent track/folder
- `DELETE_ORIGINAL`: Whether to delete the original file after import

If auto-import is enabled and `OBS_OUTPUT_DIR` is not accessible, ReapOBS will **not** start recording.

### Security Considerations for Auto-Import

- **File Permissions**: Ensure that the OBS output directory is only writable by trusted users
- **Network Paths**: Avoid using network paths for `OBS_OUTPUT_DIR` as they may introduce security risks
- **File Validation**: The auto-import feature only imports files with extensions listed in `VIDEO_EXTENSIONS`
- **Original File Deletion**: Be cautious with `DELETE_ORIGINAL = true` as deleted files cannot be recovered

### Multi-Machine Setup

For multi-machine setups where OBS runs on a different computer:

1. Set `OBS_WEBSOCKET_URL` to point to the remote machine: `obsws://remote-ip:4455/password`
2. Set `OBS_OUTPUT_DIR` to a network path accessible from your REAPER machine
3. Ensure the network path is mounted and writable
4. Consider using NFS or Samba for file sharing

---

## Recommended Workflow

1. **Open OBS Studio** and configure your video scene (camera, screen capture, etc.)
2. **Open REAPER** and set up your audio project (tracks, inputs, monitoring levels)
3. **Arm the desired tracks** in REAPER for recording (click the red arm button on each track)
4. **Press your assigned shortcut** (e.g., `Shift+R`) to start both applications recording simultaneously
5. **Perform your recording**  audio in REAPER, video in OBS
6. **Press the same shortcut** to stop both
7. If auto-import is enabled, the latest video file is imported under the `Videos` folder track and aligned to `REC START`
8. Audio is recorded to your REAPER media path. Video remains in OBS output by default; use **Save As -> Copy all media into project directory** when finalizing
9. **Edit your project** with audio and video synchronized

---

## Synchronization Notes

- There is a small delay (typically under 100 ms) between OBS and REAPER starting because the obs-cmd call takes a moment to execute.
- The scripts start **OBS first, then REAPER**, so the video file will be slightly longer at the beginning. The audio recording starts slightly after the video recording begins.
- Imported video is aligned to the latest `REC START` marker automatically. You can still fine-tune manually if needed.
- If you use **PipeWire**, both REAPER and OBS share the same audio graph, which simplifies audio routing and can improve synchronization.
- For the most reliable sync in post-production, play a few **clap or click** transients before your actual performance. The sharp transient waveform is easy to align visually in any video editor.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `obs-cmd: command not found` | Check `OBS_CMD_PATH` in `reapobs_config.lua`. Run `which obs-cmd` in a terminal to find the actual path. |
| `Connection refused` | Make sure OBS is running and the WebSocket Server is enabled: **OBS  Tools  WebSocket Server Settings  Enable**. |
| `Authentication failed` | Verify the password in `OBS_WEBSOCKET_URL` matches what is set in OBS WebSocket Server Settings. |
| REAPER records but OBS doesn't | Check the REAPER console for error output. Test obs-cmd manually: `obs-cmd --websocket obsws://localhost:4455 recording start`. |
| OBS records but REAPER doesn't | Verify that at least one track in REAPER is armed for recording. |
| Scripts don't appear in Actions | Re-load them: **Actions  Show Action List  New action...  Load ReaScript...**. |
| `Permission denied` on obs-cmd | Run `chmod +x /usr/local/bin/obs-cmd`. |
| Significant audio/video sync offset | Use a clap or click reference at the start and adjust in post. You can also try setting `REQUIRE_OBS = false` and experimenting with the order of operations. |
| Auto-import not working | Ensure `AUTO_IMPORT_VIDEO = true` and `OBS_OUTPUT_DIR` is correctly set in `reapobs_config.lua`. |
| Recording does not start with Auto-Import Error | `AUTO_IMPORT_VIDEO = true` requires a valid/readable `OBS_OUTPUT_DIR`. Fix the path or disable auto-import. |
| Video files not found | Set OBS Recording Format to MP4 and ensure `VIDEO_EXTENSIONS` includes `.mp4`. |

---

## Audio Stack Notes

On modern Debian and Ubuntu systems, **PipeWire** replaces both PulseAudio and JACK as the primary audio server. REAPER and OBS can both use PipeWire simultaneously:

- **REAPER** works with ALSA, JACK, or PipeWire (via the `pipewire-jack` compatibility layer)
- **OBS Studio** works with PulseAudio and PipeWire natively
- When both applications use PipeWire, audio routing between them is straightforward via tools like `qpwgraph` or `Helvum`

If you need help setting up your Linux audio stack for low-latency recording, refer to the [REAPER Linux audio guide](https://wiki.cockos.com/wiki/index.php/Linux_Audio) and the [PipeWire documentation](https://pipewire.pages.freedesktop.org/pipewire/).

---

## Security Considerations

### WebSocket Security

- **Password Protection**: Always use a strong password for your OBS WebSocket server, especially if accessible over a network
- **Firewall**: Restrict access to the WebSocket port (default 4455) to trusted IP addresses only
- **Local Only**: For most users, keeping the WebSocket server on localhost is sufficient and most secure

### Auto-Import Security

- **File System Permissions**: Ensure that `OBS_OUTPUT_DIR` has appropriate permissions. The directory should be readable by the REAPER user but not writable by untrusted users
- **File Type Validation**: The auto-import feature only processes files with extensions listed in `VIDEO_EXTENSIONS`. Do not add executable file extensions to this list
- **Network Paths**: Be cautious when using network paths for `OBS_OUTPUT_DIR`. Ensure the network share is secure and only accessible to trusted users
- **Malicious Files**: REAPER will attempt to parse imported video files. While video files are generally safe, be aware that malicious files could potentially exploit vulnerabilities in REAPER's media parsing

### Shell Command Injection Prevention

All shell commands in ReapOBS use the `shell_escape()` function to properly escape arguments, preventing command injection attacks. The escaping follows the standard approach of replacing single quotes with escaped single quotes.

---

## Uninstallation

```bash
# Remove ReapOBS scripts
rm -rf ~/.config/REAPER/Scripts/ReapOBS/

# Optionally remove obs-cmd
sudo rm /usr/local/bin/obs-cmd
```

Also remove the actions from REAPER's Action List:
1. Open **Actions  Show Action List**
2. Select each ReapOBS action
3. Click **Delete action** (or simply leave them  they won't do anything without the scripts present)

---

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

- **This project is Linux-only by design.** Please do not add Windows or macOS code, paths, or compatibility layers.
- Bug reports and feature requests: [GitHub Issues](https://github.com/Zesseth/ReapOBS/issues)
- For code changes, please follow the existing Lua style (2-space indentation, descriptive variable names, error handling with `pcall`)
- All user-configurable options should have comprehensive validation with clear error messages
- Use the shared library system (`reapobs_common.lua`) for new functionality to avoid code duplication

---

## License

GNU General Public License v2.0  see [LICENSE](LICENSE) for the full text.

> This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

---

## Acknowledgments

- [leafac/reaper](https://github.com/leafac/reaper) by Leandro Facchinetti  the original inspiration for REAPER + OBS recording synchronization
- [REAPER](https://www.reaper.fm/) by Cockos Incorporated
- [OBS Studio](https://obsproject.com/) by the OBS Project
- [obs-cmd](https://github.com/grigio/obs-cmd) by grigio  the CLI tool that makes this integration possible
- The REAPER ReaScript community for documentation and examples
