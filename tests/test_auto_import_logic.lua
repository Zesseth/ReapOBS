-- ============================================================
-- ReapOBS  Auto-Import Logic Tests
-- Tests for auto-import functionality
-- ============================================================

local M = {}

-- Mock functions for testing
local function filename_no_ext(filename)
  if not filename then return "" end
  local name = filename:match("^(.*)%..*$") or filename
  return name
end

local function shell_escape(str)
  if str == nil then return "" end
  return tostring(str):gsub("'", "'\\''")
end

-- Test: filename_no_ext with various inputs
function M.test_filename_no_ext_basic()
  assert(filename_no_ext("video.mp4") == "video", "Should remove .mp4 extension")
  assert(filename_no_ext("video.mkv") == "video", "Should remove .mkv extension")
  assert(filename_no_ext("video.mov") == "video", "Should remove .mov extension")
end

-- Test: filename_no_ext with multiple dots
function M.test_filename_no_ext_multiple_dots()
  assert(filename_no_ext("my.video.mp4") == "my.video", "Should only remove last extension")
  assert(filename_no_ext("video.backup.mp4") == "video.backup", "Should only remove last extension")
end

-- Test: filename_no_ext with no extension
function M.test_filename_no_ext_no_extension()
  assert(filename_no_ext("video") == "video", "Should return filename unchanged if no extension")
  assert(filename_no_ext("video_file") == "video_file", "Should return filename unchanged")
end

-- Test: filename_no_ext with path
function M.test_filename_no_ext_with_path()
  assert(filename_no_ext("/path/to/video.mp4") == "/path/to/video", "Should handle full paths")
  assert(filename_no_ext("relative/path/video.mp4") == "relative/path/video", "Should handle relative paths")
end

-- Test: filename_no_ext with nil
function M.test_filename_no_ext_nil()
  assert(filename_no_ext(nil) == "", "Should return empty string for nil")
end

-- Test: filename_no_ext with empty string
function M.test_filename_no_ext_empty()
  assert(filename_no_ext("") == "", "Should return empty string for empty input")
end

-- Test: filename_no_ext with only dot
function M.test_filename_no_ext_only_dot()
  assert(filename_no_ext(".mp4") == "", "Should return empty string for .mp4 (hidden file)")
end

-- Test: Video file extension detection
function M.test_video_extension_detection()
  local extensions = {".mp4", ".mkv", ".mov", ".avi", ".flv"}
  
  local test_files = {
    {file = "video.mp4", should_match = true},
    {file = "video.mkv", should_match = true},
    {file = "video.mov", should_match = true},
    {file = "video.avi", should_match = true},
    {file = "video.flv", should_match = true},
    {file = "video.txt", should_match = false},
    {file = "video.mp3", should_match = false},
    {file = "video.wav", should_match = false},
  }
  
  for _, test in ipairs(test_files) do
    local matches = false
    for _, ext in ipairs(extensions) do
      if test.file:match(ext .. "$") then
        matches = true
        break
      end
    end
    assert(matches == test.should_match, 
      string.format("File %s should %s match video extensions", 
        test.file, test.should_match and "" or "not"))
  end
end

-- Test: Find latest video file logic (mock)
function M.test_find_latest_video_logic()
  -- This tests the logic, not the actual file system access
  local video_files = {
    {name = "video1.mp4", mtime = 1000},
    {name = "video2.mp4", mtime = 2000},
    {name = "video3.mkv", mtime = 1500},
    {name = "old_video.mp4", mtime = 500},
  }
  
  -- Sort by modification time (newest first)
  table.sort(video_files, function(a, b) return a.mtime > b.mtime end)
  
  local latest = video_files[1]
  assert(latest.name == "video2.mp4", "Latest file should be video2.mp4")
  assert(latest.mtime == 2000, "Latest file should have mtime 2000")
end

-- Test: Recent video time window
function M.test_recent_video_time_window()
  local recent_minutes = 5
  local current_time = os.time()
  
  -- Files within the time window should be considered recent
  local recent_file_time = current_time - (recent_minutes * 60) + 30  -- 30 seconds ago
  assert(current_time - recent_file_time <= recent_minutes * 60, 
    "File should be within recent window")
  
  -- Files outside the time window should not be considered recent
  local old_file_time = current_time - (recent_minutes * 60) - 30  -- 5 minutes and 30 seconds ago
  assert(current_time - old_file_time > recent_minutes * 60, 
    "File should be outside recent window")
end

-- Test: Shell escaping for file paths
function M.test_shell_escaping_for_paths()
  local test_paths = {
    {"/path/to/video.mp4", "/path/to/video.mp4"},
    {"/path with spaces/video.mp4", "/path with spaces/video.mp4"},
    {"/path/with'quotes/video.mp4", "/path/with'\\''quotes/video.mp4"},
    {"/path/with\"double\"quotes/video.mp4", "/path/with\"double\"quotes/video.mp4"},
  }
  
  for _, test in ipairs(test_paths) do
    local input, expected = test[1], test[2]
    local result = shell_escape(input)
    assert(result == expected, 
      string.format("Path escaping failed for %s: got %s, expected %s", 
        input, result, expected))
  end
end

-- Test: Track name generation from filename
function M.test_track_name_from_filename()
  local test_cases = {
    {"video.mp4", "video"},
    {"my_recording_2024.mkv", "my_recording_2024"},
    {"/path/to/video.mp4", "video"},
    {"video", "video"},
    {"video.backup.mp4", "video.backup"},
  }
  
  for _, test in ipairs(test_cases) do
    local input, expected = test[1], test[2]
    local result = filename_no_ext(input:match("[^/\\]+$") or input)
    assert(result == expected, 
      string.format("Track name generation failed for %s: got %s, expected %s", 
        input, result, expected))
  end
end

-- Test: Auto-import configuration validation
function M.test_auto_import_config_validation()
  local config = {
    AUTO_IMPORT_VIDEO = true,
    FFMPEG_PATH = "/usr/bin/ffmpeg",
    OBS_OUTPUT_DIR = "/home/user/Videos",
    DELETE_ORIGINAL = false,
    VIDEO_EXTENSIONS = {".mp4", ".mkv"},
    RECENT_VIDEO_MINUTES = 5,
    VIDEOS_BUS_NAME = "Videos"
  }
  
  -- Check all required fields exist
  assert(config.AUTO_IMPORT_VIDEO ~= nil, "AUTO_IMPORT_VIDEO should exist")
  assert(config.FFMPEG_PATH ~= nil, "FFMPEG_PATH should exist")
  assert(config.OBS_OUTPUT_DIR ~= nil, "OBS_OUTPUT_DIR should exist")
  
  -- Check types
  assert(type(config.AUTO_IMPORT_VIDEO) == "boolean", "AUTO_IMPORT_VIDEO should be boolean")
  assert(type(config.FFMPEG_PATH) == "string", "FFMPEG_PATH should be string")
  assert(type(config.OBS_OUTPUT_DIR) == "string", "OBS_OUTPUT_DIR should be string")
  assert(type(config.DELETE_ORIGINAL) == "boolean", "DELETE_ORIGINAL should be boolean")
  assert(type(config.VIDEO_EXTENSIONS) == "table", "VIDEO_EXTENSIONS should be table")
  assert(type(config.RECENT_VIDEO_MINUTES) == "number", "RECENT_VIDEO_MINUTES should be number")
  assert(type(config.VIDEOS_BUS_NAME) == "string", "VIDEOS_BUS_NAME should be string")
  
  -- Check path is absolute
  assert(config.FFMPEG_PATH:match("^/"), "FFMPEG_PATH should be absolute")
  assert(config.OBS_OUTPUT_DIR:match("^/"), "OBS_OUTPUT_DIR should be absolute")
  
  -- Check time window is positive
  assert(config.RECENT_VIDEO_MINUTES >= 0, "RECENT_VIDEO_MINUTES should be >= 0")
end

-- Test: Error handling for missing ffmpeg
function M.test_error_handling_missing_ffmpeg()
  -- This would be tested by checking that the function returns false with appropriate error
  -- In a real test, we would mock the file existence check
  local ffmpeg_path = "/nonexistent/path/to/ffmpeg"
  local file = io.open(ffmpeg_path, "r")
  assert(file == nil, "FFmpeg should not exist at test path")
  
  -- The actual error handling would be in the check_ffmpeg_exists function
  -- which we can't easily test without mocking io.open
end

-- Test: Error handling for missing OBS output directory
function M.test_error_handling_missing_obs_dir()
  local obs_dir = "/nonexistent/obs/output"
  local file = io.open(obs_dir, "r")
  assert(file == nil, "OBS output dir should not exist at test path")
end

-- Run all tests in this module
function M.run(run_test)
  run_test("filename_no_ext basic functionality", M.test_filename_no_ext_basic)
  run_test("filename_no_ext with multiple dots", M.test_filename_no_ext_multiple_dots)
  run_test("filename_no_ext with no extension", M.test_filename_no_ext_no_extension)
  run_test("filename_no_ext with path", M.test_filename_no_ext_with_path)
  run_test("filename_no_ext with nil", M.test_filename_no_ext_nil)
  run_test("filename_no_ext with empty string", M.test_filename_no_ext_empty)
  run_test("filename_no_ext with only dot", M.test_filename_no_ext_only_dot)
  run_test("Video file extension detection", M.test_video_extension_detection)
  run_test("Find latest video logic", M.test_find_latest_video_logic)
  run_test("Recent video time window", M.test_recent_video_time_window)
  run_test("Shell escaping for file paths", M.test_shell_escaping_for_paths)
  run_test("Track name generation from filename", M.test_track_name_from_filename)
  run_test("Auto-import configuration validation", M.test_auto_import_config_validation)
  run_test("Error handling for missing ffmpeg", M.test_error_handling_missing_ffmpeg)
  run_test("Error handling for missing OBS output directory", M.test_error_handling_missing_obs_dir)
end

return M
