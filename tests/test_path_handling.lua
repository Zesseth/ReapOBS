-- ============================================================
-- ReapOBS  Path Handling Tests
-- Tests for path validation and handling functions
-- ============================================================

local M = {}

-- Mock path validation functions
local function is_absolute_path(path)
  if path == nil then return false end
  return path:match("^/") ~= nil
end

local function path_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Test: Absolute path detection
function M.test_absolute_path_detection()
  assert(is_absolute_path("/usr/bin/obs-cmd") == true, "Absolute path should be detected")
  assert(is_absolute_path("/home/user/file") == true, "Absolute path with home should be detected")
  assert(is_absolute_path("relative/path") == false, "Relative path should not be detected")
  assert(is_absolute_path("./file") == false, "Relative path with ./ should not be detected")
  assert(is_absolute_path("../file") == false, "Relative path with ../ should not be detected")
end

-- Test: Path existence checking
function M.test_path_existence()
  -- Test with a path that should exist
  local exists = path_exists("/usr/bin")
  assert(exists == true, "Existing path /usr/bin should be detected")
  
  -- Test with a path that likely doesn't exist
  local not_exists = path_exists("/nonexistent/path/12345")
  assert(not not_exists, "Non-existent path should not be detected")
end

-- Test: Configuration path validation
function M.test_config_path_validation()
  local valid_paths = {
    "/usr/bin/obs-cmd",
    "/usr/local/bin/obs-cmd",
    "/home/user/bin/obs-cmd",
    "/opt/obs-cmd/obs-cmd"
  }
  
  for _, path in ipairs(valid_paths) do
    assert(is_absolute_path(path), "Path " .. path .. " should be absolute")
  end
  
  local invalid_paths = {
    "obs-cmd",
    "./obs-cmd",
    "../bin/obs-cmd",
    "~/obs-cmd"
  }
  
  for _, path in ipairs(invalid_paths) do
    assert(not is_absolute_path(path), "Path " .. path .. " should not be absolute")
  end
end

-- Test: OBS output directory path validation
function M.test_obs_output_dir_validation()
  local valid_dirs = {
    "/home/user/Videos",
    "/media/user/recordings",
    "/mnt/nas/obs_output"
  }
  
  for _, dir in ipairs(valid_dirs) do
    assert(is_absolute_path(dir), "OBS output dir " .. dir .. " should be absolute")
  end
end

-- Test: FFmpeg path validation
function M.test_ffmpeg_path_validation()
  local valid_paths = {
    "/usr/bin/ffmpeg",
    "/usr/local/bin/ffmpeg",
    "/opt/ffmpeg/bin/ffmpeg"
  }
  
  for _, path in ipairs(valid_paths) do
    assert(is_absolute_path(path), "FFmpeg path " .. path .. " should be absolute")
  end
end

-- Test: Path with spaces
function M.test_path_with_spaces()
  local path = "/path with spaces/file"
  assert(is_absolute_path(path), "Path with spaces should be absolute")
  -- Note: The actual escaping is tested in shell_escaping tests
end

-- Test: Path with special characters
function M.test_path_with_special_chars()
  local path = "/path/with-special_chars/file"
  assert(is_absolute_path(path), "Path with special chars should be absolute")
end

-- Test: Path with unicode characters
function M.test_path_with_unicode()
  local path = "/path/with/文件/file"
  assert(is_absolute_path(path), "Path with unicode should be absolute")
end

-- Test: Empty path
function M.test_empty_path()
  local path = ""
  assert(not is_absolute_path(path), "Empty path should not be absolute")
end

-- Test: Nil path
function M.test_nil_path()
  -- This would be caught by configuration validation before path checking
  -- Just testing that our function doesn't crash
  local ok, err = pcall(function()
    local result = is_absolute_path(nil)
    return result
  end)
  assert(ok, "Path validation should handle nil without crashing")
end

-- Test: Very long path
function M.test_long_path()
  local path = "/" .. string.rep("very_long_directory_name_", 20) .. "/file"
  assert(is_absolute_path(path), "Long path should be absolute")
  assert(#path > 100, "Long path should be > 100 chars")
end

-- Test: Root path
function M.test_root_path()
  local path = "/"
  assert(is_absolute_path(path), "Root path should be absolute")
end

-- Test: Path with trailing slash
function M.test_path_with_trailing_slash()
  local path = "/usr/bin/"
  assert(is_absolute_path(path), "Path with trailing slash should be absolute")
end

-- Run all tests in this module
function M.run(run_test)
  run_test("Absolute path detection works", M.test_absolute_path_detection)
  run_test("Path existence checking works", M.test_path_existence)
  run_test("Configuration path validation works", M.test_config_path_validation)
  run_test("OBS output directory validation works", M.test_obs_output_dir_validation)
  run_test("FFmpeg path validation works", M.test_ffmpeg_path_validation)
  run_test("Path with spaces handling works", M.test_path_with_spaces)
  run_test("Path with special characters handling works", M.test_path_with_special_chars)
  run_test("Path with unicode handling works", M.test_path_with_unicode)
  run_test("Empty path handling works", M.test_empty_path)
  run_test("Nil path handling works", M.test_nil_path)
  run_test("Long path handling works", M.test_long_path)
  run_test("Root path handling works", M.test_root_path)
  run_test("Path with trailing slash handling works", M.test_path_with_trailing_slash)
end

return M
