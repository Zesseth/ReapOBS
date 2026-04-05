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
local OBS_WEBSOCKET_URL = "obsws://localhost:4455"

-- Set to true to add a project marker at the recording stop position
local ADD_MARKER_ON_STOP = true

-- Marker name prefix for stop markers
local STOP_MARKER_PREFIX = "REC STOP"

-- Set to false to stop REAPER recording even if OBS connection fails
-- Set to true to require OBS to be available before REAPER stops recording
local REQUIRE_OBS = true

-- Set to true to show status messages in the REAPER console
local DEBUG = true
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
-- Alternative: reaper.ExecProcess() can also invoke binaries,
-- but io.popen() is simpler and captures stdout/stderr here.
-- ------------------------------------------------------------
local function obs_cmd(command)
  local full_cmd = OBS_CMD_PATH .. " --websocket " .. OBS_WEBSOCKET_URL .. " " .. command .. " 2>&1"
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
-- Helper: verify the obs-cmd binary exists at the configured path
-- ------------------------------------------------------------
local function check_obs_cmd_exists()
  local f = io.open(OBS_CMD_PATH, "r")
  if f then
    f:close()
    log("obs-cmd found at: " .. OBS_CMD_PATH)
    return true
  else
    log("ERROR: obs-cmd not found at: " .. OBS_CMD_PATH)
    return false
  end
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
  log("ReapOBS: Stopping synchronized recording...")

  -- Guard: nothing to stop if not recording
  if not is_reaper_recording() then
    log("Not currently recording, nothing to stop.")
    return
  end

  -- Stop REAPER recording first (action 1016 = Transport: Stop)
  reaper.Main_OnCommand(1016, 0)

  -- Optionally mark the stop position
  if ADD_MARKER_ON_STOP then
    add_marker(STOP_MARKER_PREFIX)
  end

  -- Stop OBS recording – failure here is non-critical since REAPER has already stopped
  if not check_obs_cmd_exists() then
    log("WARNING: obs-cmd not found – cannot stop OBS recording.")
  else
    local obs_ok, obs_out = obs_cmd("recording stop")
    if not obs_ok then
      log("WARNING: Failed to stop OBS recording. Output: " .. obs_out)
    end
  end

  log("ReapOBS: Recording stopped successfully.")
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(stop_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
