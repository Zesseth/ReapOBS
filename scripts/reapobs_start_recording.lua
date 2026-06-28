-- ============================================================
-- ReapOBS  Start Recording
-- Starts both REAPER and OBS Studio recording simultaneously
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

-- Load common functions and configuration
local common = dofile(reaper.GetResourcePath() .. "/Scripts/ReapOBS/reapobs_common.lua")

-- Extract commonly used functions for cleaner code
local log = common.log
local obs_cmd = common.obs_cmd
local is_reaper_recording = common.is_reaper_recording
local check_obs_cmd_exists = common.check_obs_cmd_exists
local check_obs_output_dir = common.check_obs_output_dir
local add_marker = common.add_marker
local config = common.config

-- =================== USER CONFIGURATION ====================
-- Configuration is now centralized in reapobs_config.lua
-- You can override specific settings here if needed
-- Example: local ADD_MARKER_ON_START = true
-- =================== END CONFIGURATION =====================

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

  if config.AUTO_IMPORT_VIDEO then
    local out_ok, out_err = check_obs_output_dir()
    if not out_ok then
      reaper.ShowMessageBox(
        "Auto-import is enabled, but OBS output directory is not accessible:\n\n" ..
        config.OBS_OUTPUT_DIR .. "\n\n" ..
        "Recording was not started. Fix OBS_OUTPUT_DIR or disable AUTO_IMPORT_VIDEO.\n\n" ..
        out_err,
        "ReapOBS: Auto-Import Error",
        0
      )
      return
    end
  end

  -- Test OBS connection with 'info' command
  local conn_ok, conn_out = obs_cmd("info")
  if not conn_ok then
    if config.REQUIRE_OBS then
      reaper.ShowMessageBox(
        "Could not connect to OBS Studio.\n\n" ..
        "Make sure OBS is running and the WebSocket server is enabled:\n" ..
        "OBS  Tools  WebSocket Server Settings  Enable\n\n" ..
        "WebSocket URL: " .. config.OBS_WEBSOCKET_URL .. "\n\n" ..
        "obs-cmd output:\n" .. conn_out,
        "ReapOBS: OBS Connection Failed",
        0
      )
      return
    else
      log("WARNING: OBS connection failed but REQUIRE_OBS is false  continuing anyway.")
    end
  end

  -- Start OBS recording
  local obs_ok, obs_out = obs_cmd("recording start")
  if not obs_ok then
    -- obs-cmd returns non-zero if OBS is already recording  handle gracefully
    if obs_out:lower():find("already") then
      log("OBS is already recording  treating as success.")
    elseif config.REQUIRE_OBS then
      reaper.ShowMessageBox(
        "Failed to start OBS recording.\n\n" ..
        "obs-cmd output:\n" .. obs_out,
        "ReapOBS: OBS Start Failed",
        0
      )
      return
    else
      log("WARNING: Failed to start OBS recording but REQUIRE_OBS is false  starting REAPER anyway.")
    end
  end

  -- Start REAPER recording (use constant from config)
  reaper.Main_OnCommand(config.REAPER_ACTION_RECORD, 0)

  -- Optionally mark the start position
  if config.ADD_MARKER_ON_START then
    add_marker(config.MARKER_PREFIX)
  end

  log("ReapOBS: Recording started successfully.")
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(start_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
