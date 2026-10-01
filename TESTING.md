# Testing ReapOBS

Short guide for testing this branch (`vibe/fix-stop-marker-and-encoding-72adcb`).

## What this branch fixes

1. **REC STOP marker position** (issue #10): the stop marker now lands at the
   real stop position instead of `0.0`. The play position is captured *before*
   the transport stop command is issued.
2. **Corrupted UTF-8 characters** (issue #11): raw control bytes in scripts,
   README and install.sh were replaced with the intended characters
   (`→`, `–`, box-drawing).

## 1. Automated tests (no REAPER/OBS needed)

Requires standalone Lua 5.3/5.4 (`sudo apt install lua5.3`):

```bash
cd /mnt/data/Repos/ReapOBS
lua5.3 tests/test_bug_regressions.lua
```

All 5 tests must print `PASS`. The tests use a mock REAPER API and stub
`obs-cmd`/`ffmpeg` binaries in a sandbox — they never touch your real
REAPER project or OBS.

## 2. Update the installed scripts

The scripts run from `~/.config/REAPER/Scripts/ReapOBS/`; the repo copies
must be deployed there before live testing:

```bash
cp /mnt/data/Repos/ReapOBS/scripts/*.lua ~/.config/REAPER/Scripts/ReapOBS/
```

(Or run `./install.sh` and answer `y` to the overwrite prompts — it will
also offer to install obs-cmd and the toolbar icon.)

Backups of the previous installed versions live next to the directory as
`ReapOBS.backup-*`. REAPER action IDs and the `Shift+R` shortcut are bound to
the file paths, so they keep working after the update — no action reload
needed.

## 3. Prerequisites for a live test

- **OBS Studio running**, and **Tools → WebSocket Server Settings →
  WebSocket Server enabled** (port 4455, no password by default).
- OBS **Settings → Output → Recording → Recording Format = MP4**.
- obs-cmd in `OBS_CMD_PATH` (`which obs-cmd`).
- OBS output directory exists and is readable (`OBS_OUTPUT_DIR` in
  `reapobs_config.lua`, default `/mnt/data/VideoRecording`).
- In REAPER, at least one track armed for recording.

Quick connection check without recording:

```bash
obs-cmd --websocket obsws://localhost:4455 info
```

## 4. Live test procedure

1. Open OBS, then REAPER; arm a track.
2. Press `Shift+R` (or click the toolbar button). Both REAPER and OBS
   should start recording; a `REC START` marker appears at the start
   position.
3. Record a minute or so; ideally clap once at the start for sync
   reference.
4. Press `Shift+R` again. Both stop. Verify:
   - `REC STOP` marker is at the position where the transport stopped
     (not at 0.0) — this is the branch's main fix.
   - OBS really stopped recording (no lingering "REC" in OBS).
   - The new MP4 appears in `OBS_OUTPUT_DIR`.
   - With auto-import enabled, a `Videos` folder track with a child track
     containing the imported video appears in REAPER, aligned to the
   `REC START` marker.

## 5. How it is used and updated

- **Use**: `reapobs_toggle_recording.lua` bound to `Shift+R` (and/or the
  toolbar button) starts/stops REAPER and OBS together. The separate
  start/stop scripts exist for one-way actions. All options live in
  `~/.config/REAPER/Scripts/ReapOBS/reapobs_config.lua`.
- **Update**: `git pull` the repo, then re-copy the scripts as in step 2.
  Keep an eye on config changes: copy `reapobs_config.lua` only if you
  accept new defaults.
- **Debug**: set `DEBUG = true` in `reapobs_config.lua` to log every
  obs-cmd call and auto-import step to the REAPER console
  (View → Console).

## Rollback

```bash
cp ~/.config/REAPER/Scripts/ReapOBS.backup-*/.lua \
   ~/.config/REAPER/Scripts/ReapOBS/
```

(after a backup from step 2 exists).
