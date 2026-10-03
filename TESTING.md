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
./run_tests.sh
```

`run_tests.sh` checks the Lua interpreter, runs a syntax check
(`luac -p`) on every script and test file, and then runs the full
regression suite. It is the single command to run before committing.

The same suite can be run directly:

```bash
lua5.3 tests/test_bug_regressions.lua
```

All 8 tests must print `PASS`. The tests use a mock REAPER API and stub
`obs-cmd`/`ffmpeg` binaries in a sandbox — they never touch your real
REAPER project or OBS.

## 2. Update the installed scripts

`~/.config/REAPER/Scripts/ReapOBS` is a symlink to this repo's `scripts/`
directory, so REAPER always loads the current working copy — a plain
`git pull` (or branch checkout) is enough, no file copying needed:

```bash
ls -la ~/.config/REAPER/Scripts/ReapOBS
# ReapOBS -> /mnt/data/Repos/ReapOBS/scripts
```

If the symlink is missing, recreate it:

```bash
ln -s /mnt/data/Repos/ReapOBS/scripts ~/.config/REAPER/Scripts/ReapOBS
```

(Remove any regular directory with that name first. `./install.sh` copies
files instead of using the symlink — do not run it on a symlinked setup
unless you want a copy-based installation again.)

REAPER action IDs and the `Shift+R` shortcut are bound to the script paths,
which resolve through the symlink, so they keep working across branch
switches. Previous copy-based versions are preserved as
`ReapOBS.backup-*` / `ReapOBS.copied-*` directories.

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
  `reapobs_config.lua` in this repo (loaded through the symlink).
- **Update**: `git pull` in the repo — the symlink makes the new scripts
  live immediately. Keep an eye on config changes: a pulled
  `reapobs_config.lua` replaces your local settings since it is the same
  file.
- **Debug**: set `DEBUG = true` in `reapobs_config.lua` to log every
  obs-cmd call and auto-import step to the REAPER console
  (View → Console).

## Rollback

Restore the last copy-based installation:

```bash
rm ~/.config/REAPER/Scripts/ReapOBS   # removes the symlink only
mv ~/.config/REAPER/Scripts/ReapOBS.copied-20261001 \
   ~/.config/REAPER/Scripts/ReapOBS
```
