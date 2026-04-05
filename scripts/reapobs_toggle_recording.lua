-- ============================================================
-- ReapOBS – Toggle Recording
-- Toggles both REAPER and OBS Studio recording based on current state
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

-- Set to true to add a project marker at the recording start position
local ADD_MARKER_ON_START = true

-- Marker name prefix for start markers
local MARKER_PREFIX = "REC START"

-- Set to true to add a project marker at the recording stop position
local ADD_MARKER_ON_STOP = true

-- Marker name prefix for stop markers
local STOP_MARKER_PREFIX = "REC STOP"

-- Set to false to start REAPER recording even if OBS connection fails
-- Set to true to require OBS to be available before REAPER starts recording
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
-- Start logic (inline – REAPER Lua has no cross-script imports)
-- ------------------------------------------------------------
local function start_recording()
  log("ReapOBS: Starting synchronized recording...")

  if is_reaper_recording() then
    log("WARNING: REAPER is already recording. Nothing to do.")
    return
  end

  if not check_obs_cmd_exists() then
    reaper.ShowMessageBox(
      "obs-cmd was not found at:\n" .. OBS_CMD_PATH ..
      "\n\nPlease install obs-cmd or update OBS_CMD_PATH in this script.\n" ..
      "Run 'which obs-cmd' in a terminal to find its location.",
      "ReapOBS: obs-cmd Not Found",
      0
    )
    return
  end

  local conn_ok, conn_out = obs_cmd("info")
  if not conn_ok then
    if REQUIRE_OBS then
      reaper.ShowMessageBox(
        "Could not connect to OBS Studio.\n\n" ..
        "Make sure OBS is running and the WebSocket server is enabled:\n" ..
        "OBS → Tools → WebSocket Server Settings → Enable\n\n" ..
        "WebSocket URL: " .. OBS_WEBSOCKET_URL .. "\n\n" ..
        "obs-cmd output:\n" .. conn_out,
        "ReapOBS: OBS Connection Failed",
        0
      )
      return
    else
      log("WARNING: OBS connection failed but REQUIRE_OBS is false – continuing anyway.")
    end
  end

  local obs_ok, obs_out = obs_cmd("recording start")
  if not obs_ok then
    if obs_out:lower():find("already") then
      log("OBS is already recording – treating as success.")
    elseif REQUIRE_OBS then
      reaper.ShowMessageBox(
        "Failed to start OBS recording.\n\n" ..
        "obs-cmd output:\n" .. obs_out,
        "ReapOBS: OBS Start Failed",
        0
      )
      return
    else
      log("WARNING: Failed to start OBS recording but REQUIRE_OBS is false – starting REAPER anyway.")
    end
  end

  -- Start REAPER recording (action 1013 = Transport: Record)
  reaper.Main_OnCommand(1013, 0)

  if ADD_MARKER_ON_START then
    add_marker(MARKER_PREFIX)
  end

  log("ReapOBS: Recording started successfully.")
end

-- ------------------------------------------------------------
-- Stop logic (inline – REAPER Lua has no cross-script imports)
-- ------------------------------------------------------------
local function stop_recording()
  log("ReapOBS: Stopping synchronized recording...")

  if not is_reaper_recording() then
    log("Not currently recording, nothing to stop.")
    return
  end

  -- Stop REAPER recording first (action 1016 = Transport: Stop)
  reaper.Main_OnCommand(1016, 0)

  if ADD_MARKER_ON_STOP then
    add_marker(STOP_MARKER_PREFIX)
  end

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

-- ------------------------------------------------------------
-- Main: toggle based on current recording state
-- ------------------------------------------------------------
local function toggle_recording()
  if is_reaper_recording() then
    stop_recording()
  else
    start_recording()
  end
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(toggle_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
