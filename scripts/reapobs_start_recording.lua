-- ============================================================
-- ReapOBS – Start Recording
-- Starts both REAPER and OBS Studio recording simultaneously
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

-- Set to true to add a project marker at the recording start position
local ADD_MARKER_ON_START = true

-- Marker name prefix for start markers
local MARKER_PREFIX = "REC START"

-- Set to false to start REAPER recording even if OBS connection fails
-- Set to true to require OBS to be available before REAPER starts recording
local REQUIRE_OBS = true

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
-- Main: start synchronized recording
-- ------------------------------------------------------------
local function start_recording()
  log("ReapOBS: Starting synchronized recording...")

  -- Guard: don't start if already recording
  if is_reaper_recording() then
    log("WARNING: REAPER is already recording. Nothing to do.")
    return
  end

  -- Guard: obs-cmd binary must exist and be executable
  local cmd_ok, cmd_err = check_obs_cmd_exists()
  if not cmd_ok then
    reaper.ShowMessageBox(cmd_err, "ReapOBS: obs-cmd Problem", 0)
    return
  end

  -- Test OBS connection with 'info' command
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

  -- Start OBS recording
  local obs_ok, obs_out = obs_cmd("recording start")
  if not obs_ok then
    -- obs-cmd returns non-zero if OBS is already recording – handle gracefully
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

  -- Store the recording start position for auto-import alignment
  local rec_pos = reaper.GetPlayPosition()
  reaper.SetExtState("ReapOBS", "rec_start_pos", tostring(rec_pos), false)
  log("Stored recording start position: " .. tostring(rec_pos))

  -- Optionally mark the start position
  if ADD_MARKER_ON_START then
    add_marker(MARKER_PREFIX)
  end

  log("ReapOBS: Recording started successfully.")
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(start_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
