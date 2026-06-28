-- ============================================================
-- ReapOBS  Toggle Recording
-- Toggles both REAPER and OBS Studio recording based on current state
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
local auto_import_latest_video = common.auto_import_latest_video

-- get_action_context() must be called before any other REAPER API calls
local _, _, SECTION_ID, CMD_ID = reaper.get_action_context()

-- =================== USER CONFIGURATION ====================
-- Configuration is now centralized in reapobs_config.lua
-- You can override specific settings here if needed
-- =================== END CONFIGURATION =====================

-- ------------------------------------------------------------
-- Helper: update toolbar toggle state
-- ------------------------------------------------------------
local function update_toggle_state(state)
  reaper.SetToggleCommandState(SECTION_ID, CMD_ID, state)
  reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
end

-- ------------------------------------------------------------
-- Start logic
-- ------------------------------------------------------------
local function start_recording()
  log("ReapOBS: Starting synchronized recording...")

  if is_reaper_recording() then
    log("WARNING: REAPER is already recording. Nothing to do.")
    return
  end

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

  local obs_ok, obs_out = obs_cmd("recording start")
  if not obs_ok then
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

  if config.ADD_MARKER_ON_START then
    add_marker(config.MARKER_PREFIX)
  end

  update_toggle_state(1)
  log("ReapOBS: Recording started successfully.")
end

-- ------------------------------------------------------------
-- Stop logic
-- ------------------------------------------------------------
local function stop_recording()
  if not is_reaper_recording() then
    log("Not currently recording, nothing to stop.")
    return
  end

  log("ReapOBS: Stopping synchronized recording...")

  -- Stop REAPER recording first (use constant from config)
  reaper.Main_OnCommand(config.REAPER_ACTION_STOP, 0)

  if config.ADD_MARKER_ON_STOP then
    add_marker(config.STOP_MARKER_PREFIX)
  end

  -- Stop OBS recording  alert the user if this fails
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

  -- Auto-import the latest video if enabled
  if config.AUTO_IMPORT_VIDEO then
    local import_ok, import_err = auto_import_latest_video()
    if not import_ok then
      log("WARNING: Auto-import failed: " .. (import_err or "Unknown error"))
      reaper.ShowMessageBox(
        "Recording stopped successfully, but auto-import failed:\n\n" ..
        (import_err or "Unknown error"),
        "ReapOBS: Auto-Import Warning",
        0
      )
    end
  end

  update_toggle_state(0)
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

-- Initialize toggle state to match current recording state
update_toggle_state(is_reaper_recording() and 1 or 0)

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(toggle_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
