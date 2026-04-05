-- ============================================================
-- ReapOBS – Stop Recording
-- Stops both REAPER and OBS Studio recording simultaneously
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

-- =================== USER CONFIGURATION ====================
-- Path to obs-cmd binary. Find it with: which obs-cmd
local OBS_CMD_PATH = "/usr/local/bin/obs-cmd"

-- OBS WebSocket connection URL
-- Format: obsws://hostname:port or obsws://hostname:port/password
-- Default OBS WebSocket port is 4455
-- If you disabled authentication in OBS, omit the password part
-- Note: password must not contain single quotes (')
local OBS_WEBSOCKET_URL = "obsws://localhost:4455"

-- Set to true to add a project marker at the recording stop position
local ADD_MARKER_ON_STOP = true

-- Marker name prefix for stop markers
local STOP_MARKER_PREFIX = "REC STOP"

-- Note: REQUIRE_OBS is not used in the stop script. Stopping REAPER
-- recording always proceeds regardless of OBS availability.

-- Set to true to show status messages in the REAPER console
-- Useful for troubleshooting; error dialogs always appear regardless of this setting
local DEBUG = false
-- =================== END CONFIGURATION =====================

-- ------------------------------------------------------------
-- Helper: log a message to the REAPER console (DEBUG only)
-- ------------------------------------------------------------
local function log(msg)
  if DEBUG then
    reaper.ShowConsoleMsg("[ReapOBS] " .. msg .. "\n")
  end
end

-- ------------------------------------------------------------
-- Helper: run an obs-cmd command, return success + output
-- Uses timeout(1) to prevent REAPER from hanging if obs-cmd
-- or the OBS WebSocket connection becomes unresponsive.
-- ------------------------------------------------------------
local function obs_cmd(command)
  local full_cmd = "timeout 5 '" .. OBS_CMD_PATH .. "' --websocket '" .. OBS_WEBSOCKET_URL .. "' " .. command .. " 2>&1"
  log("Running: " .. full_cmd)

  local file = io.popen(full_cmd)
  if not file then
    log("ERROR: io.popen() failed to launch obs-cmd")
    return false, ""
  end

  local output = file:read("*a")
  -- In Lua 5.3 (REAPER's Lua), file:close() returns: ok, "exit", exitcode
  local ok, _, exitcode = file:close()
  local success = (ok == true) and (exitcode == 0)

  log("obs-cmd output: " .. (output or ""))
  log("obs-cmd exit code: " .. tostring(exitcode))

  -- timeout(1) returns exit code 124 when the command times out
  if exitcode == 124 then
    log("ERROR: obs-cmd timed out after 5 seconds")
  end

  return success, output or ""
end

-- ------------------------------------------------------------
-- Helper: check if REAPER is currently recording
-- reaper.GetPlayState() bit 2 (value 4) = recording
-- ------------------------------------------------------------
local function is_reaper_recording()
  return reaper.GetPlayState() & 4 == 4
end

-- ------------------------------------------------------------
-- Helper: verify the obs-cmd binary exists and is executable
-- ------------------------------------------------------------
local function check_obs_cmd_exists()
  local f = io.open(OBS_CMD_PATH, "r")
  if f then
    f:close()
  else
    local msg = "obs-cmd not found at: " .. OBS_CMD_PATH
    log("ERROR: " .. msg)
    return false, msg .. "\n\nPlease install obs-cmd or update OBS_CMD_PATH in this script.\nRun 'which obs-cmd' in a terminal to find its location."
  end
  -- Verify execute permission
  local rc = os.execute("test -x '" .. OBS_CMD_PATH .. "'")
  if not rc then
    local msg = "obs-cmd is not executable: " .. OBS_CMD_PATH
    log("ERROR: " .. msg)
    return false, msg .. "\n\nFix with: chmod +x " .. OBS_CMD_PATH
  end
  log("obs-cmd found at: " .. OBS_CMD_PATH)
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: add a project marker at the current play/edit position
-- ------------------------------------------------------------
local function add_marker(name)
  local pos = reaper.GetPlayPosition()
  reaper.AddProjectMarker(0, false, pos, 0, name, -1)
  log("Marker added: '" .. name .. "' at position " .. tostring(pos))
end

-- ------------------------------------------------------------
-- Main: stop synchronized recording
-- ------------------------------------------------------------
local function stop_recording()
  -- Guard: nothing to stop if not recording
  if not is_reaper_recording() then
    log("Not currently recording, nothing to stop.")
    return
  end

  log("ReapOBS: Stopping synchronized recording...")

  -- Stop REAPER recording first (action 1016 = Transport: Stop)
  reaper.Main_OnCommand(1016, 0)

  -- Optionally mark the stop position
  if ADD_MARKER_ON_STOP then
    add_marker(STOP_MARKER_PREFIX)
  end

  -- Stop OBS recording – alert the user if this fails
  local cmd_ok, cmd_err = check_obs_cmd_exists()
  if not cmd_ok then
    log("WARNING: " .. (cmd_err or "obs-cmd not available"))
    reaper.ShowMessageBox(
      "REAPER recording was stopped, but obs-cmd is not available.\n" ..
      "OBS Studio may still be recording.\n\n" ..
      cmd_err .. "\n\nPlease check OBS Studio manually.",
      "ReapOBS: OBS Stop Warning",
      0
    )
  else
    local obs_ok, obs_out = obs_cmd("recording stop")
    if not obs_ok then
      log("WARNING: Failed to stop OBS recording. Output: " .. obs_out)
      reaper.ShowMessageBox(
        "REAPER recording was stopped, but OBS may still be recording.\n\n" ..
        "Please check OBS Studio manually.\n\n" ..
        "obs-cmd output:\n" .. obs_out,
        "ReapOBS: OBS Stop Warning",
        0
      )
    end
  end

  log("ReapOBS: Recording stopped successfully.")
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(stop_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
