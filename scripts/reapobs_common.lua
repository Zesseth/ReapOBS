-- ============================================================
-- ReapOBS  Common Functions Library
-- Shared functions for all ReapOBS scripts
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

-- Load configuration
local config = dofile(reaper.GetResourcePath() .. "/Scripts/ReapOBS/reapobs_config.lua")

-- Extract configuration values to local variables for easier access
local OBS_CMD_PATH = config.OBS_CMD_PATH
local OBS_WEBSOCKET_URL = config.OBS_WEBSOCKET_URL
local DEBUG = config.DEBUG
local FFMPEG_PATH = config.FFMPEG_PATH
local OBS_OUTPUT_DIR = config.OBS_OUTPUT_DIR
local VIDEO_EXTENSIONS = config.VIDEO_EXTENSIONS
local RECENT_VIDEO_MINUTES = config.RECENT_VIDEO_MINUTES
local VIDEOS_BUS_NAME = config.VIDEOS_BUS_NAME
local DELETE_ORIGINAL = config.DELETE_ORIGINAL
local REAPER_ACTION_RECORD = config.REAPER_ACTION_RECORD
local REAPER_ACTION_STOP = config.REAPER_ACTION_STOP

-- ============================================================
-- Helper Functions
-- ============================================================

-- ------------------------------------------------------------
-- Helper: log a message to the REAPER console (DEBUG only)
-- ------------------------------------------------------------
local function log(msg)
  if DEBUG then
    reaper.ShowConsoleMsg("[ReapOBS] " .. msg .. "\n")
  end
end

-- ------------------------------------------------------------
-- Helper: escape shell arguments to prevent command injection
-- Based on: https://stackoverflow.com/questions/35778981/lua-escape-shell-command-arguments
-- ------------------------------------------------------------
local function shell_escape(str)
  -- Replace single quotes with escaped single quotes
  -- This is the standard way to escape strings for shell commands
  return tostring(str):gsub("'", "'\\''")
end

-- ------------------------------------------------------------
-- Helper: run an obs-cmd command, return success + output
-- Uses timeout(5) to prevent REAPER from hanging if obs-cmd
-- or the OBS WebSocket connection becomes unresponsive.
-- ------------------------------------------------------------
local function obs_cmd(command)
  local full_cmd = "timeout 5 '" .. shell_escape(OBS_CMD_PATH) .. "' --websocket '" .. shell_escape(OBS_WEBSOCKET_URL) .. "' " .. command .. " 2>&1"
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
    return false, msg .. "\n\nPlease install obs-cmd or update OBS_CMD_PATH in reapobs_config.lua.\nRun 'which obs-cmd' in a terminal to find its location."
  end
  -- Verify execute permission
  local rc = os.execute("test -x '" .. shell_escape(OBS_CMD_PATH) .. "'")
  if not rc then
    local msg = "obs-cmd is not executable: " .. OBS_CMD_PATH
    log("ERROR: " .. msg)
    return false, msg .. "\n\nFix with: chmod +x " .. OBS_CMD_PATH
  end
  log("obs-cmd found at: " .. OBS_CMD_PATH)
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: verify ffmpeg binary exists and is executable
-- ------------------------------------------------------------
local function check_ffmpeg_exists()
  local f = io.open(FFMPEG_PATH, "r")
  if f then
    f:close()
  else
    local msg = "ffmpeg not found at: " .. FFMPEG_PATH
    log("ERROR: " .. msg)
    return false, msg .. "\n\nPlease install ffmpeg or update FFMPEG_PATH in reapobs_config.lua.\nRun 'which ffmpeg' in a terminal to find its location."
  end
  -- Verify execute permission
  local rc = os.execute("test -x '" .. shell_escape(FFMPEG_PATH) .. "'")
  if not rc then
    local msg = "ffmpeg is not executable: " .. FFMPEG_PATH
    log("ERROR: " .. msg)
    return false, msg .. "\n\nFix with: chmod +x " .. FFMPEG_PATH
  end
  log("ffmpeg found at: " .. FFMPEG_PATH)
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: verify OBS output directory exists and is readable
-- ------------------------------------------------------------
local function check_obs_output_dir()
  local rc = os.execute("test -d '" .. shell_escape(OBS_OUTPUT_DIR) .. "' && test -r '" .. shell_escape(OBS_OUTPUT_DIR) .. "'")
  if not rc then
    local msg = "OBS output directory not found or not readable: " .. OBS_OUTPUT_DIR
    log("WARNING: " .. msg)
    return false, msg
  end
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
-- Helper: validate OBS WebSocket URL format
-- ------------------------------------------------------------
local function validate_websocket_url(url)
  if type(url) ~= "string" or url == "" then
    return false, "URL must be a non-empty string"
  end
  
  if not url:match("^obsws://") then
    return false, "URL must start with obsws://"
  end
  
  -- Check for invalid characters (basic check)
  if url:match("[<>\"\\]") then
    return false, "URL contains invalid characters"
  end
  
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: get the recording start position
-- Returns the position where recording started, or current position if not recording
-- ------------------------------------------------------------
local function get_rec_start_position()
  if is_reaper_recording() then
    return reaper.GetPlayPosition()
  end
  
  -- If not recording, return current edit position
  return reaper.GetCursorPosition()
end

-- ============================================================
-- Auto-Import Functions
-- ============================================================

-- ------------------------------------------------------------
-- Helper: find the latest video file in OBS output directory
-- Uses shell commands since LuaFileSystem is optional
-- ------------------------------------------------------------
local function find_latest_video()
  -- Check if OBS_OUTPUT_DIR exists and is readable
  local rc = os.execute("test -d '" .. shell_escape(OBS_OUTPUT_DIR) .. "' && test -r '" .. shell_escape(OBS_OUTPUT_DIR) .. "'")
  if not rc then
    log("ERROR: OBS output directory does not exist or is not readable: " .. OBS_OUTPUT_DIR)
    return nil, "OBS output directory not found or not readable"
  end

  -- Build find command to get the most recently modified video file
  local extensions_pattern = ""
  for _, ext in ipairs(VIDEO_EXTENSIONS) do
    extensions_pattern = extensions_pattern .. "-name '*'" .. ext .. " -o "
  end
  -- Remove the trailing " -o "
  extensions_pattern = extensions_pattern:sub(1, -4)
  
  local find_cmd = "find '" .. shell_escape(OBS_OUTPUT_DIR) .. "' -type f \\( " .. extensions_pattern .. " \\) -mmin -" .. RECENT_VIDEO_MINUTES .. " -printf '%T@ %p\\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-"
  
  log("Finding latest video with: " .. find_cmd)
  
  local file = io.popen(find_cmd)
  if not file then
    log("ERROR: Failed to execute find command")
    return nil, "Failed to search for video files"
  end
  
  local latest_file = file:read("*l")
  file:close()
  
  if not latest_file or latest_file == "" then
    log("No recent video files found in: " .. OBS_OUTPUT_DIR)
    return nil, "No recent video files found"
  end
  
  log("Found latest video file: " .. latest_file)
  return latest_file, nil
end

-- ------------------------------------------------------------
-- Helper: convert video file to a format suitable for REAPER
-- ------------------------------------------------------------
local function convert_video(input_file, output_file)
  if not input_file or not output_file then
    return false, "Input and output file paths are required"
  end
  
  -- Check if ffmpeg is available
  local ffmpeg_ok, ffmpeg_err = check_ffmpeg_exists()
  if not ffmpeg_ok then
    return false, "ffmpeg not available: " .. ffmpeg_err
  end
  
  -- Check if input file exists
  local rc = os.execute("test -f '" .. shell_escape(input_file) .. "'")
  if not rc then
    return false, "Input file not found: " .. input_file
  end
  
  -- Check if output directory is writable
  local output_dir = output_file:match("^(.*[/\\])[^/\\]*$") or "."
  rc = os.execute("test -w '" .. shell_escape(output_dir) .. "'")
  if not rc then
    return false, "Output directory not writable: " .. output_dir
  end
  
  -- Build ffmpeg command
  -- Convert to a format that REAPER can handle well (e.g., MP4 with AAC audio)
  local ffmpeg_cmd = string.format(
    "timeout 300 '" .. shell_escape(FFMPEG_PATH) .. "' -i '%s' -c:v libx264 -crf 18 -preset fast -c:a aac -b:a 192k -movflags +faststart '%s' 2>&1",
    shell_escape(input_file),
    shell_escape(output_file)
  )
  
  log("Converting video with: " .. ffmpeg_cmd)
  
  local file = io.popen(ffmpeg_cmd)
  if not file then
    return false, "Failed to start ffmpeg conversion"
  end
  
  local output = file:read("*a")
  local ok, _, exitcode = file:close()
  
  if not ok or exitcode ~= 0 then
    log("ERROR: ffmpeg conversion failed with exit code: " .. tostring(exitcode))
    log("ffmpeg output: " .. output)
    return false, "Video conversion failed: " .. (output or "Unknown error")
  end
  
  log("Video conversion completed successfully")
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: get filename without extension
-- ------------------------------------------------------------
local function filename_no_ext(filename)
  if not filename then return "" end
  local name = filename:match("^(.*)%..*$") or filename
  return name
end

-- ------------------------------------------------------------
-- Helper: find the latest marker position by name prefix
-- ------------------------------------------------------------
local function find_latest_marker_position(name_prefix)
  if type(name_prefix) ~= "string" or name_prefix == "" then
    return nil
  end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total_markers = (num_markers or 0) + (num_regions or 0)
  local latest_pos = nil
  local has_enum_markers3 = reaper.APIExists and reaper.APIExists("EnumProjectMarkers3")

  for i = 0, total_markers - 1 do
    local retval, is_region, pos, _, marker_name
    if has_enum_markers3 then
      retval, is_region, pos, _, marker_name = reaper.EnumProjectMarkers3(0, i)
    else
      retval, is_region, pos, _, marker_name = reaper.EnumProjectMarkers(i)
    end

    if retval > 0 and not is_region and type(marker_name) == "string" then
      if marker_name:sub(1, #name_prefix) == name_prefix then
        if (not latest_pos) or pos > latest_pos then
          latest_pos = pos
        end
      end
    end
  end

  return latest_pos
end

-- ------------------------------------------------------------
-- Helper: get or create the Videos bus track
-- ------------------------------------------------------------
local function get_or_create_videos_bus()
  -- Check if a track with VIDEOS_BUS_NAME already exists
  local num_tracks = reaper.CountTracks(0)
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetTrackName(track)
    if track_name == VIDEOS_BUS_NAME then
      log("Found existing Videos bus track")
      return track
    end
  end
  
  -- Create a new track for videos
  log("Creating new Videos bus track")
  reaper.InsertTrackAtIndex(num_tracks, true)
  local new_track = reaper.GetTrack(0, num_tracks)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", VIDEOS_BUS_NAME, true)
  
  -- Set track to be a folder (bus)
  reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 1)
  
  return new_track
end

-- ------------------------------------------------------------
-- Helper: insert a child track in a folder track
-- ------------------------------------------------------------
local function insert_child_in_folder(folder_track, child_name)
  if not folder_track then
    return nil, "Folder track is required"
  end
  
  local folder_index = reaper.GetMediaTrackInfo_Value(folder_track, "IP_TRACKNUMBER") - 1
  local num_tracks = reaper.CountTracks(0)
  local closing_track_index = nil
  local closing_depth = nil

  -- Find the current folder-closing track.
  local depth = 1
  for i = folder_index + 1, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local track_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    depth = depth + track_depth

    if depth <= 0 then
      closing_track_index = i
      closing_depth = track_depth
      break
    end
  end

  local insert_index
  local child_close_depth
  local old_closer

  if closing_track_index ~= nil then
    -- Append as the new last child:
    -- 1) remove folder-closing depth from old closer
    -- 2) insert new track after old closer
    -- 3) apply old closing depth to new child
    old_closer = reaper.GetTrack(0, closing_track_index)
    if old_closer then
      reaper.SetMediaTrackInfo_Value(old_closer, "I_FOLDERDEPTH", 0)
    end

    insert_index = closing_track_index + 1
    child_close_depth = closing_depth
    if not child_close_depth or child_close_depth >= 0 then
      child_close_depth = -1
    end
  else
    -- No explicit closer found (new/empty folder at end): close with new child.
    insert_index = num_tracks
    child_close_depth = -1
  end

  reaper.InsertTrackAtIndex(insert_index, true)
  local child_track = reaper.GetTrack(0, insert_index)
  if not child_track then
    if old_closer and closing_depth then
      reaper.SetMediaTrackInfo_Value(old_closer, "I_FOLDERDEPTH", closing_depth)
    end
    return nil, "Failed to create child track"
  end

  reaper.GetSetMediaTrackInfo_String(child_track, "P_NAME", child_name, true)
  reaper.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", child_close_depth)
  
  return child_track
end

-- ------------------------------------------------------------
-- Helper: import video file to a track
-- ------------------------------------------------------------
local function import_video_to_track(track, video_path, target_position)
  if not track or not video_path then
    return false, "Track and video path are required"
  end
  
  -- Check if file exists
  local rc = os.execute("test -f '" .. shell_escape(video_path) .. "'")
  if not rc then
    return false, "Video file not found: " .. video_path
  end
  
  local track_index = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
  if track_index < 0 then
    return false, "Invalid target track index"
  end

  local import_position = tonumber(target_position) or 0
  if import_position < 0 then
    import_position = 0
  end

  -- InsertMedia mode: mode&3==0 + 512 + high word as absolute track index.
  -- This targets the correct track regardless of current selection/touched track.
  local insert_mode = 512 + (track_index << 16)
  local original_cursor = reaper.GetCursorPosition()

  local function restore_cursor()
    reaper.SetEditCurPos(original_cursor, false, false)
  end

  local function get_file_size_bytes(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
  end

  local function sleep_seconds(seconds)
    os.execute("sleep " .. tostring(seconds))
  end

  local function try_insert_media(path)
    local item_count_before = reaper.CountTrackMediaItems(track)
    reaper.SetEditCurPos(import_position, false, false)

    local imported = reaper.InsertMedia(path, insert_mode)
    if imported ~= 1 then
      return false, "REAPER failed to import media file"
    end

    local item_count_after = reaper.CountTrackMediaItems(track)
    if item_count_after <= item_count_before then
      return false, "Media import did not create an item on target track"
    end

    local imported_item = reaper.GetTrackMediaItem(track, item_count_after - 1)
    if not imported_item then
      return false, "Could not get imported media item"
    end

    reaper.SetMediaItemInfo_Value(imported_item, "D_POSITION", import_position)
    local item_length = reaper.GetMediaItemInfo_Value(imported_item, "D_LENGTH")
    if not item_length or item_length <= 0 then
      reaper.DeleteTrackMediaItem(track, imported_item)
      return false, "Imported media item has zero length"
    end

    reaper.UpdateItemInProject(imported_item)
    return true, nil
  end

  local max_import_attempts = 6
  local last_err = nil
  for attempt = 1, max_import_attempts do
    local ok, err = try_insert_media(video_path)
    if ok then
      restore_cursor()
      reaper.UpdateArrange()
      log("Successfully imported video to track: " .. video_path)
      return true, nil
    end

    last_err = err
    local size_bytes = get_file_size_bytes(video_path)
    local size_info = size_bytes and (" (size: " .. tostring(size_bytes) .. " bytes)") or ""
    log("WARNING: Import attempt " .. tostring(attempt) .. " failed: " .. tostring(err) .. size_info)

    if attempt < max_import_attempts then
      sleep_seconds(1)
    end
  end

  -- Fallback path for formats REAPER cannot parse directly from OBS output.
  local precision_time = (reaper.time_precise and reaper.time_precise()) or os.clock()
  local temp_converted = string.format("/tmp/reapobs-import-%d.mp4", math.floor(precision_time * 1000))
  log("Trying ffmpeg conversion fallback: " .. temp_converted)

  local converted_ok, converted_err = convert_video(video_path, temp_converted)
  if not converted_ok then
    restore_cursor()
    reaper.UpdateArrange()
    return false, "Import failed after retries: " .. tostring(last_err) .. ". Conversion failed: " .. tostring(converted_err)
  end

  local fallback_ok, fallback_err = try_insert_media(temp_converted)
  local cleanup_ok = os.execute("rm -f '" .. shell_escape(temp_converted) .. "'")
  if not cleanup_ok then
    log("WARNING: Failed to remove temporary converted file: " .. temp_converted)
  end

  restore_cursor()
  reaper.UpdateArrange()

  if not fallback_ok then
    return false, "Import of converted file failed: " .. tostring(fallback_err)
  end
  
  log("Successfully imported converted video to track: " .. video_path)
  return true, nil
end

-- ------------------------------------------------------------
-- Helper: auto-import the latest video after recording stops
-- ------------------------------------------------------------
local function auto_import_latest_video()
  if not config.AUTO_IMPORT_VIDEO then
    log("Auto-import is disabled")
    return true, nil
  end
  
  log("Starting auto-import process...")
  
  -- Find the latest video file
  local video_file, err = find_latest_video()
  if not video_file then
    log("WARNING: " .. (err or "No video file found"))
    return false, "No video file found: " .. (err or "Unknown error")
  end
  
  -- Get or create the Videos bus
  local videos_bus = get_or_create_videos_bus()
  if not videos_bus then
    return false, "Failed to get or create Videos bus"
  end
  
  -- Create a child track for this video
  local base_name = filename_no_ext(video_file:match("[^/\\]+$"))
  local child_track, err = insert_child_in_folder(videos_bus, base_name)
  if not child_track then
    return false, "Failed to create child track: " .. err
  end

  local import_position = find_latest_marker_position(config.MARKER_PREFIX)
  if import_position then
    log("Aligning imported video to marker '" .. config.MARKER_PREFIX .. "' at position " .. tostring(import_position))
  else
    import_position = 0
    log("WARNING: Start marker '" .. config.MARKER_PREFIX .. "' not found; importing at project start")
  end
  
  -- Import the video to the track
  local ok, err = import_video_to_track(child_track, video_file, import_position)
  if not ok then
    return false, "Failed to import video: " .. err
  end
  
  -- Optionally delete the original file
  if DELETE_ORIGINAL then
    local rc = os.execute("rm -f '" .. shell_escape(video_file) .. "'")
    if rc then
      log("Deleted original video file: " .. video_file)
    else
      log("WARNING: Failed to delete original video file: " .. video_file)
    end
  end
  
  log("Auto-import completed successfully")
  return true, nil
end

-- ============================================================
-- Public API
-- ============================================================

return {
  -- Configuration
  config = config,
  
  -- Helper functions
  log = log,
  obs_cmd = obs_cmd,
  is_reaper_recording = is_reaper_recording,
  check_obs_cmd_exists = check_obs_cmd_exists,
  check_ffmpeg_exists = check_ffmpeg_exists,
  check_obs_output_dir = check_obs_output_dir,
  add_marker = add_marker,
  shell_escape = shell_escape,
  validate_websocket_url = validate_websocket_url,
  get_rec_start_position = get_rec_start_position,
  
  -- Auto-import functions
  find_latest_video = find_latest_video,
  convert_video = convert_video,
  filename_no_ext = filename_no_ext,
  get_or_create_videos_bus = get_or_create_videos_bus,
  insert_child_in_folder = insert_child_in_folder,
  import_video_to_track = import_video_to_track,
  auto_import_latest_video = auto_import_latest_video,
  
  -- Constants
  REAPER_ACTION_RECORD = REAPER_ACTION_RECORD,
  REAPER_ACTION_STOP = REAPER_ACTION_STOP
}
