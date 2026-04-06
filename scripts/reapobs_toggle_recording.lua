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
-- Note: password must not contain single quotes (')
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
-- Useful for troubleshooting; error dialogs always appear regardless of this setting
local DEBUG = false

-- ---- Auto-import video settings ----
-- Set to true to automatically import OBS video into the REAPER project after recording
local AUTO_IMPORT_VIDEO = true

-- Path to ffmpeg binary. Find it with: which ffmpeg
local FFMPEG_PATH = "/usr/bin/ffmpeg"

-- Output format for the converted video file
local VIDEO_FORMAT = "mp4"

-- ffmpeg arguments for conversion. Default remuxes without re-encoding (fast).
-- Change to e.g. "-c:v libx264 -c:a aac" to re-encode.
local FFMPEG_ARGS = "-c:v copy -c:a aac"

-- Set to true to delete the original OBS recording after successful conversion
local DELETE_ORIGINAL = false

-- OBS output directory where OBS saves recordings
-- Find in OBS: Settings → Output → Recording Path
-- Must be an absolute path
local OBS_OUTPUT_DIR = ""
-- =================== END CONFIGURATION =====================

-- get_action_context() must be called before any other REAPER API calls
local _, _, SECTION_ID, CMD_ID = reaper.get_action_context()

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
-- Helper: update toolbar toggle state
-- ------------------------------------------------------------
local function update_toggle_state(state)
  reaper.SetToggleCommandState(SECTION_ID, CMD_ID, state)
  reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
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
-- Helper: get the recording start position for video alignment
-- Tries ExtState first, then falls back to scanning for the
-- most recent REC START marker.
-- ------------------------------------------------------------
local function get_rec_start_position()
  local stored = reaper.GetExtState("ReapOBS", "rec_start_pos")
  if stored and stored ~= "" then
    local pos = tonumber(stored)
    if pos then
      log("Recording start position from ExtState: " .. tostring(pos))
      return pos
    end
  end
  local num_markers = reaper.CountProjectMarkers(0)
  for i = num_markers - 1, 0, -1 do
    local _, _, pos, _, name, _ = reaper.EnumProjectMarkers(i)
    if name and name:find("^" .. MARKER_PREFIX) then
      log("Recording start position from marker: " .. tostring(pos))
      return pos
    end
  end
  log("WARNING: Could not determine recording start position, defaulting to 0")
  return 0
end

-- ------------------------------------------------------------
-- Helper: find the most recent video file in a directory
-- ------------------------------------------------------------
local function find_latest_video(dir)
  local cmd = "find '" .. dir .. "' -maxdepth 1 -type f " ..
    "\\( -name '*.mkv' -o -name '*.mp4' -o -name '*.avi' " ..
    "-o -name '*.mov' -o -name '*.flv' -o -name '*.ts' -o -name '*.webm' \\) " ..
    "-mmin -5 -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-"
  log("Scanning for video: " .. cmd)
  local file = io.popen(cmd)
  if not file then return nil end
  local result = file:read("*a")
  file:close()
  if result then
    result = result:gsub("^%s+", ""):gsub("%s+$", "")
  end
  if not result or result == "" then return nil end
  return result
end

-- ------------------------------------------------------------
-- Helper: check if ffmpeg is available
-- ------------------------------------------------------------
local function check_ffmpeg_exists()
  local f = io.open(FFMPEG_PATH, "r")
  if f then
    f:close()
  else
    log("ERROR: ffmpeg not found at: " .. FFMPEG_PATH)
    return false
  end
  local rc = os.execute("test -x '" .. FFMPEG_PATH .. "'")
  if not rc then
    log("ERROR: ffmpeg is not executable: " .. FFMPEG_PATH)
    return false
  end
  return true
end

-- ------------------------------------------------------------
-- Helper: convert video using ffmpeg
-- Returns success (bool) and the output path on success.
-- ------------------------------------------------------------
local function convert_video(input_path, output_dir)
  local basename = input_path:match("([^/]+)$") or "video"
  local name_no_ext = basename:match("(.+)%..+$") or basename
  local output_path = output_dir .. "/" .. name_no_ext .. "." .. VIDEO_FORMAT

  local input_ext = input_path:match("%.([^%.]+)$")
  if input_ext and input_ext:lower() == VIDEO_FORMAT:lower() then
    if input_path == output_path then
      log("Video is already at the destination in the correct format.")
      return true, output_path
    end
    log("Video is already in " .. VIDEO_FORMAT .. " format, copying directly.")
    local cp_ok = os.execute("cp '" .. input_path .. "' '" .. output_path .. "'")
    if cp_ok then
      return true, output_path
    else
      log("ERROR: Failed to copy video file.")
      return false, nil
    end
  end

  local cmd = "'" .. FFMPEG_PATH .. "' -y -i '" .. input_path .. "' " ..
    FFMPEG_ARGS .. " '" .. output_path .. "' 2>&1"
  log("Converting video: " .. cmd)

  local file = io.popen(cmd)
  if not file then
    log("ERROR: Failed to run ffmpeg")
    return false, nil
  end
  local output = file:read("*a")
  local ok, _, exitcode = file:close()
  local success = (ok == true) and (exitcode == 0)

  if not success then
    log("ERROR: ffmpeg conversion failed (exit " .. tostring(exitcode) .. "): " .. (output or ""))
    return false, nil
  end

  log("Video converted successfully: " .. output_path)
  return true, output_path
end

-- ------------------------------------------------------------
-- Helper: extract filename without path or extension
-- ------------------------------------------------------------
local function filename_no_ext(path)
  local basename = path:match("([^/]+)$") or "video"
  return basename:match("(.+)%..+$") or basename
end

-- ------------------------------------------------------------
-- Helper: find or create the "Videos" folder (bus) track
-- Creates at position 0 (topmost) if it does not exist.
-- Does not touch any other tracks.
-- ------------------------------------------------------------
local function get_or_create_videos_bus()
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    local fd = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if name == "Videos" and fd == 1 then
      log("Found existing Videos bus at track index " .. tostring(i))
      return track, i
    end
  end
  reaper.InsertTrackAtIndex(0, true)
  local bus = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(bus, "P_NAME", "Videos", true)
  reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)
  log("Created Videos bus at track index 0")
  return bus, 0
end

-- ------------------------------------------------------------
-- Helper: insert a new child track at the end of a folder
-- Properly adjusts folder depth values so existing tracks
-- are not affected.
-- ------------------------------------------------------------
local function insert_child_in_folder(bus_idx, track_name)
  local count = reaper.CountTracks(0)
  local depth = 0
  local last_child_idx = bus_idx

  for i = bus_idx + 1, count - 1 do
    local track = reaper.GetTrack(0, i)
    local fd = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    depth = depth + fd
    if depth < 0 then
      last_child_idx = i
      reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", fd + 1)
      break
    end
    last_child_idx = i
  end

  local insert_idx
  if last_child_idx == bus_idx then
    insert_idx = bus_idx + 1
  else
    insert_idx = last_child_idx + 1
  end

  reaper.InsertTrackAtIndex(insert_idx, true)
  local new_track = reaper.GetTrack(0, insert_idx)
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
  reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
  log("Created child track '" .. track_name .. "' at index " .. tostring(insert_idx))
  return new_track
end

-- ------------------------------------------------------------
-- Helper: import video file onto a track at a given position
-- Uses low-level API to avoid side effects on other tracks.
-- ------------------------------------------------------------
local function import_video_to_track(track, video_path, position)
  local source = reaper.PCM_Source_CreateFromFile(video_path)
  if not source then
    log("ERROR: Failed to create PCM source from: " .. video_path)
    return false
  end

  local length = reaper.GetMediaSourceLength(source)
  if not length or length <= 0 then
    log("WARNING: Could not determine video length, using 1 second fallback")
    length = 1
  end

  local item = reaper.AddMediaItemToTrack(track)
  if not item then
    log("ERROR: Failed to create media item on track")
    return false
  end

  local take = reaper.AddTakeToMediaItem(item)
  if not take then
    log("ERROR: Failed to add take to media item")
    return false
  end

  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
  reaper.UpdateArrange()

  log("Video imported at position " .. tostring(position) .. ", length " .. tostring(length))
  return true
end

-- ------------------------------------------------------------
-- Auto-import: detect, convert, and import OBS video
-- ------------------------------------------------------------
local function auto_import_video()
  if not AUTO_IMPORT_VIDEO then
    log("Auto-import is disabled.")
    return
  end

  if OBS_OUTPUT_DIR == "" then
    log("Auto-import skipped: OBS_OUTPUT_DIR is not configured.")
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import skipped: OBS_OUTPUT_DIR is not set. " ..
      "Configure it in the script to enable auto-import.\n")
    return
  end

  if not check_ffmpeg_exists() then
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import skipped: ffmpeg not found at " ..
      FFMPEG_PATH .. ". Install with: sudo apt install ffmpeg\n")
    return
  end

  reaper.ShowConsoleMsg("[ReapOBS] Looking for OBS video in: " .. OBS_OUTPUT_DIR .. "\n")
  local video_file = find_latest_video(OBS_OUTPUT_DIR)
  if not video_file then
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import: No recent video file found in " ..
      OBS_OUTPUT_DIR .. ". Check OBS output directory setting.\n")
    return
  end
  reaper.ShowConsoleMsg("[ReapOBS] Found OBS video: " .. video_file .. "\n")

  local project_path = reaper.GetProjectPath("")
  if not project_path or project_path == "" then
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import: Could not determine REAPER project path. " ..
      "Save your project first.\n")
    return
  end

  reaper.ShowConsoleMsg("[ReapOBS] Converting video to " .. VIDEO_FORMAT .. "...\n")
  local conv_ok, converted_path = convert_video(video_file, project_path)
  if not conv_ok or not converted_path then
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import: Video conversion failed. " ..
      "Check ffmpeg installation and video file.\n")
    return
  end
  reaper.ShowConsoleMsg("[ReapOBS] Video saved to: " .. converted_path .. "\n")

  if DELETE_ORIGINAL then
    local del_ok = os.execute("rm '" .. video_file .. "'")
    if del_ok then
      log("Original video deleted: " .. video_file)
    else
      log("WARNING: Failed to delete original: " .. video_file)
    end
  end

  local rec_start = get_rec_start_position()

  reaper.Undo_BeginBlock()

  local video_name = filename_no_ext(converted_path)
  local _, bus_idx = get_or_create_videos_bus()
  local child_track = insert_child_in_folder(bus_idx, video_name)
  local import_ok = import_video_to_track(child_track, converted_path, rec_start)

  reaper.Undo_EndBlock("ReapOBS: Import OBS video", -1)

  if import_ok then
    reaper.ShowConsoleMsg("[ReapOBS] Video imported successfully on track '" ..
      video_name .. "' at position " .. string.format("%.3f", rec_start) .. "s\n")
  else
    reaper.ShowConsoleMsg("[ReapOBS] Auto-import: Failed to import video onto track.\n")
  end
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

  local cmd_ok, cmd_err = check_obs_cmd_exists()
  if not cmd_ok then
    reaper.ShowMessageBox(cmd_err, "ReapOBS: obs-cmd Problem", 0)
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

  -- Store the recording start position for auto-import alignment
  local rec_pos = reaper.GetPlayPosition()
  reaper.SetExtState("ReapOBS", "rec_start_pos", tostring(rec_pos), false)
  log("Stored recording start position: " .. tostring(rec_pos))

  if ADD_MARKER_ON_START then
    add_marker(MARKER_PREFIX)
  end

  update_toggle_state(1)
  log("ReapOBS: Recording started successfully.")
end

-- ------------------------------------------------------------
-- Stop logic (inline – REAPER Lua has no cross-script imports)
-- ------------------------------------------------------------
local function stop_recording()
  if not is_reaper_recording() then
    log("Not currently recording, nothing to stop.")
    return
  end

  log("ReapOBS: Stopping synchronized recording...")

  -- Stop REAPER recording first (action 1016 = Transport: Stop)
  reaper.Main_OnCommand(1016, 0)

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

  update_toggle_state(0)
  log("ReapOBS: Recording stopped successfully.")

  -- Auto-import OBS video into the project
  auto_import_video()
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
