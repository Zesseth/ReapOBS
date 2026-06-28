-- ============================================================
-- ReapOBS  Stop Recording
-- Stops both REAPER and OBS Studio recording simultaneously
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
local add_marker = common.add_marker
local config = common.config
local auto_import_latest_video = common.auto_import_latest_video

-- =================== USER CONFIGURATION ====================
-- Configuration is now centralized in reapobs_config.lua
-- You can override specific settings here if needed
-- =================== END CONFIGURATION =====================

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

  -- Stop REAPER recording first (use constant from config)
  reaper.Main_OnCommand(config.REAPER_ACTION_STOP, 0)

  -- Optionally mark the stop position
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

  log("ReapOBS: Recording stopped successfully.")
end

-- Run with pcall so an unexpected error never crashes REAPER
local ok, err = pcall(stop_recording)
if not ok then
  reaper.ShowConsoleMsg("[ReapOBS] Unexpected error: " .. tostring(err) .. "\n")
end
