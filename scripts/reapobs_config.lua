-- ============================================================
-- ReapOBS  Central Configuration
-- Shared configuration for all ReapOBS scripts
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

-- =================== USER CONFIGURATION ====================
-- Path to obs-cmd binary. Find it with: which obs-cmd
OBS_CMD_PATH = "/usr/local/bin/obs-cmd"

-- OBS WebSocket connection URL
-- Format: obsws://hostname:port or obsws://hostname:port/password
-- Default OBS WebSocket port is 4455
-- If you disabled authentication in OBS, omit the password part
-- Note: password must not contain single quotes (')
OBS_WEBSOCKET_URL = "obsws://localhost:4455"

-- Set to true to add a project marker at the recording start position
ADD_MARKER_ON_START = true

-- Marker name prefix for start markers
MARKER_PREFIX = "REC START"

-- Set to true to add a project marker at the recording stop position
ADD_MARKER_ON_STOP = true

-- Marker name prefix for stop markers
STOP_MARKER_PREFIX = "REC STOP"

-- Set to false to start REAPER recording even if OBS connection fails
-- Set to true to require OBS to be available before REAPER starts recording
REQUIRE_OBS = true

-- Set to true to show status messages in the REAPER console
-- Useful for troubleshooting; error dialogs always appear regardless of this setting
DEBUG = false

-- =================== AUTO-IMPORT CONFIGURATION ====================
-- Set to true to enable automatic video import after recording stops
AUTO_IMPORT_VIDEO = true

-- Path to ffmpeg binary. Find it with: which ffmpeg
FFMPEG_PATH = "/usr/bin/ffmpeg"

-- Directory where OBS saves recordings
-- Must be an absolute path
OBS_OUTPUT_DIR = "/mnt/data/VideoRecording"

-- Set to true to delete the original video file after importing to REAPER
DELETE_ORIGINAL = false

-- Video file extensions to look for when auto-importing
-- OBS should be configured to record in MP4 format for reliable auto-import.
VIDEO_EXTENSIONS = {".mp4"}

-- Time window in minutes to consider a video file as "recent" (for auto-import)
RECENT_VIDEO_MINUTES = 60

-- Name of the track/folder to create for imported videos
VIDEOS_BUS_NAME = "Videos"

-- REAPER action IDs (constants for maintainability)
REAPER_ACTION_RECORD = 1013
REAPER_ACTION_STOP = 1016
-- =================== END CONFIGURATION =====================

-- ============================================================
-- Configuration Validation
-- ============================================================

local function validate_config()
  -- Validate boolean settings
  local bool_settings = {
    "ADD_MARKER_ON_START",
    "ADD_MARKER_ON_STOP", 
    "REQUIRE_OBS",
    "DEBUG",
    "AUTO_IMPORT_VIDEO",
    "DELETE_ORIGINAL"
  }
  
  for _, setting in ipairs(bool_settings) do
    if type(_G[setting]) ~= "boolean" then
      _G[setting] = (tostring(_G[setting]):lower() == "true")
    end
  end

  -- Validate path settings
  local path_settings = {
    {"OBS_CMD_PATH", true},
    {"FFMPEG_PATH", true},
    {"OBS_OUTPUT_DIR", false}
  }
  
  for _, path_info in ipairs(path_settings) do
    local setting = path_info[1]
    local must_exist = path_info[2]
    
    if type(_G[setting]) ~= "string" or _G[setting] == "" then
      error("Configuration error: " .. setting .. " must be a non-empty string")
    end
    
    -- Check if absolute path
    if not _G[setting]:match("^/") then
      error("Configuration error: " .. setting .. " must be an absolute path (starting with /)")
    end
    
    -- Check if file/directory exists (if required)
    if must_exist then
      local f = io.open(_G[setting], "r")
      if not f then
        error("Configuration error: " .. setting .. " not found at: " .. _G[setting])
      end
      f:close()
    end
  end

  -- Validate OBS_WEBSOCKET_URL
  if type(OBS_WEBSOCKET_URL) ~= "string" or OBS_WEBSOCKET_URL == "" then
    error("Configuration error: OBS_WEBSOCKET_URL must be a non-empty string")
  end
  
  if not OBS_WEBSOCKET_URL:match("^obsws://") then
    error("Configuration error: OBS_WEBSOCKET_URL must start with obsws://")
  end

  -- Validate MARKER_PREFIX length
  if type(MARKER_PREFIX) ~= "string" or MARKER_PREFIX == "" then
    error("Configuration error: MARKER_PREFIX must be a non-empty string")
  end
  
  if #MARKER_PREFIX > 100 then
    error("Configuration error: MARKER_PREFIX must be less than 100 characters")
  end

  -- Validate STOP_MARKER_PREFIX length
  if type(STOP_MARKER_PREFIX) ~= "string" or STOP_MARKER_PREFIX == "" then
    error("Configuration error: STOP_MARKER_PREFIX must be a non-empty string")
  end
  
  if #STOP_MARKER_PREFIX > 100 then
    error("Configuration error: STOP_MARKER_PREFIX must be less than 100 characters")
  end

  -- Validate RECENT_VIDEO_MINUTES
  if type(RECENT_VIDEO_MINUTES) ~= "number" or RECENT_VIDEO_MINUTES < 0 then
    error("Configuration error: RECENT_VIDEO_MINUTES must be a positive number")
  end

  -- Validate VIDEO_EXTENSIONS
  if type(VIDEO_EXTENSIONS) ~= "table" or #VIDEO_EXTENSIONS == 0 then
    error("Configuration error: VIDEO_EXTENSIONS must be a non-empty table")
  end
  
  for _, ext in ipairs(VIDEO_EXTENSIONS) do
    if type(ext) ~= "string" or ext == "" then
      error("Configuration error: All VIDEO_EXTENSIONS entries must be non-empty strings")
    end
  end

  -- Validate VIDEOS_BUS_NAME
  if type(VIDEOS_BUS_NAME) ~= "string" or VIDEOS_BUS_NAME == "" then
    error("Configuration error: VIDEOS_BUS_NAME must be a non-empty string")
  end
end

-- Run validation when this file is loaded
local ok, err = pcall(validate_config)
if not ok then
  -- Log error to REAPER console if available
  if reaper then
    reaper.ShowConsoleMsg("[ReapOBS Config] " .. err .. "\n")
  end
  error(err)
end

return {
  -- Configuration values
  OBS_CMD_PATH = OBS_CMD_PATH,
  OBS_WEBSOCKET_URL = OBS_WEBSOCKET_URL,
  ADD_MARKER_ON_START = ADD_MARKER_ON_START,
  MARKER_PREFIX = MARKER_PREFIX,
  ADD_MARKER_ON_STOP = ADD_MARKER_ON_STOP,
  STOP_MARKER_PREFIX = STOP_MARKER_PREFIX,
  REQUIRE_OBS = REQUIRE_OBS,
  DEBUG = DEBUG,
  AUTO_IMPORT_VIDEO = AUTO_IMPORT_VIDEO,
  FFMPEG_PATH = FFMPEG_PATH,
  OBS_OUTPUT_DIR = OBS_OUTPUT_DIR,
  DELETE_ORIGINAL = DELETE_ORIGINAL,
  VIDEO_EXTENSIONS = VIDEO_EXTENSIONS,
  RECENT_VIDEO_MINUTES = RECENT_VIDEO_MINUTES,
  VIDEOS_BUS_NAME = VIDEOS_BUS_NAME,
  REAPER_ACTION_RECORD = REAPER_ACTION_RECORD,
  REAPER_ACTION_STOP = REAPER_ACTION_STOP,
  
  -- Validation function
  validate_config = validate_config
}
