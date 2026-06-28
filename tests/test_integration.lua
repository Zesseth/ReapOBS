-- ============================================================
-- ReapOBS  Integration Tests
-- Tests that require REAPER environment
-- Run this as a ReaScript within REAPER
-- ============================================================

-- Check if we're running in REAPER
if not reaper then
  error("This test must be run within REAPER")
end

local M = {}
local tests_passed = 0
local tests_failed = 0

-- Helper function to run a test and report results
local function run_test(name, test_func)
  local success, err = pcall(test_func)
  if success then
    tests_passed = tests_passed + 1
    reaper.ShowConsoleMsg("[ReapOBS Test] ✓ " .. name .. "\n")
  else
    tests_failed = tests_failed + 1
    reaper.ShowConsoleMsg("[ReapOBS Test] ✗ " .. name .. "\n")
    reaper.ShowConsoleMsg("  Error: " .. tostring(err) .. "\n")
  end
end

-- Test: REAPER API is available
function M.test_reaper_api_available()
  assert(reaper.GetPlayState ~= nil, "reaper.GetPlayState should exist")
  assert(reaper.Main_OnCommand ~= nil, "reaper.Main_OnCommand should exist")
  assert(reaper.AddProjectMarker ~= nil, "reaper.AddProjectMarker should exist")
  assert(reaper.GetPlayPosition ~= nil, "reaper.GetPlayPosition should exist")
  assert(reaper.CountTracks ~= nil, "reaper.CountTracks should exist")
  assert(reaper.GetTrack ~= nil, "reaper.GetTrack should exist")
end

-- Test: Configuration can be loaded
function M.test_config_loading()
  local config_path = reaper.GetResourcePath() .. "/Scripts/ReapOBS/scripts/reapobs_config.lua"
  
  -- Check if config file exists
  local f = io.open(config_path, "r")
  if f then
    f:close()
    
    -- Try to load it
    local config_func, err = loadfile(config_path)
    assert(config_func ~= nil, "Config file should load: " .. tostring(err))
    
    -- Try to run it
    local success, config_or_err = pcall(config_func)
    assert(success, "Config file should run without errors: " .. tostring(config_or_err))
  else
    reaper.ShowConsoleMsg("  Warning: Config file not found at " .. config_path .. "\n")
  end
end

-- Test: Common library can be loaded
function M.test_common_library_loading()
  local common_path = reaper.GetResourcePath() .. "/Scripts/ReapOBS/scripts/reapobs_common.lua"
  
  -- Check if common file exists
  local f = io.open(common_path, "r")
  if f then
    f:close()
    
    -- Try to load it
    local common_func, err = loadfile(common_path)
    assert(common_func ~= nil, "Common library should load: " .. tostring(err))
    
    -- Try to run it (it should return a table)
    local success, common_or_err = pcall(common_func)
    assert(success, "Common library should run without errors: " .. tostring(common_or_err))
    assert(type(common_or_err) == "table", "Common library should return a table")
  else
    reaper.ShowConsoleMsg("  Warning: Common library not found at " .. common_path .. "\n")
  end
end

-- Test: Script files can be loaded
function M.test_script_loading()
  local scripts = {
    "reapobs_start_recording.lua",
    "reapobs_stop_recording.lua", 
    "reapobs_toggle_recording.lua"
  }
  
  local scripts_dir = reaper.GetResourcePath() .. "/Scripts/ReapOBS/scripts/"
  
  for _, script in ipairs(scripts) do
    local script_path = scripts_dir .. script
    local f = io.open(script_path, "r")
    if f then
      f:close()
      
      -- Try to load it
      local script_func, err = loadfile(script_path)
      assert(script_func ~= nil, script .. " should load: " .. tostring(err))
    else
      reaper.ShowConsoleMsg("  Warning: Script not found: " .. script_path .. "\n")
    end
  end
end

-- Test: Play state detection
function M.test_play_state_detection()
  local state = reaper.GetPlayState()
  assert(type(state) == "number", "Play state should be a number")
  
  -- Check if recording bit is set (bit 2, value 4)
  local is_recording = (state & 4) == 4
  assert(type(is_recording) == "boolean", "Recording state should be boolean")
end

-- Test: Current position can be retrieved
function M.test_current_position()
  local pos = reaper.GetPlayPosition()
  assert(type(pos) == "number", "Play position should be a number")
  assert(pos >= 0, "Play position should be >= 0")
end

-- Test: Track counting
function M.test_track_counting()
  local num_tracks = reaper.CountTracks(0)
  assert(type(num_tracks) == "number", "Track count should be a number")
  assert(num_tracks >= 0, "Track count should be >= 0")
end

-- Test: Track access
function M.test_track_access()
  local num_tracks = reaper.CountTracks(0)
  if num_tracks > 0 then
    local track = reaper.GetTrack(0, 0)
    assert(track ~= nil, "Should be able to get first track")
    
    local _, track_name = reaper.GetTrackName(track)
    assert(type(track_name) == "string", "Track name should be a string")
  else
    reaper.ShowConsoleMsg("  Warning: No tracks in project, skipping track access test\n")
  end
end

-- Test: Marker creation (non-destructive test - just check function exists)
function M.test_marker_creation_function()
  assert(reaper.AddProjectMarker ~= nil, "AddProjectMarker function should exist")
  assert(reaper.GetPlayPosition ~= nil, "GetPlayPosition function should exist")
end

-- Test: Action execution (non-destructive - just check function exists)
function M.test_action_execution_function()
  assert(reaper.Main_OnCommand ~= nil, "Main_OnCommand function should exist")
  -- Don't actually execute actions in tests
end

-- Test: Console output function
function M.test_console_output()
  assert(reaper.ShowConsoleMsg ~= nil, "ShowConsoleMsg function should exist")
  -- Test that it doesn't crash
  reaper.ShowConsoleMsg("[ReapOBS Test] Console output test\n")
end

-- Test: Resource path retrieval
function M.test_resource_path()
  local resource_path = reaper.GetResourcePath()
  assert(type(resource_path) == "string", "Resource path should be a string")
  assert(resource_path ~= "", "Resource path should not be empty")
end

-- Test: Project state
function M.test_project_state()
  local project_path = reaper.GetProjectPath()
  -- Project path can be empty for new projects
  assert(type(project_path) == "string" or project_path == nil, "Project path should be string or nil")
end

-- Run all integration tests
function M.run()
  reaper.ShowConsoleMsg("\n[ReapOBS] Running Integration Tests...\n")
  reaper.ShowConsoleMsg(string.rep("-", 50) .. "\n")
  
  run_test("REAPER API is available", M.test_reaper_api_available)
  run_test("Configuration can be loaded", M.test_config_loading)
  run_test("Common library can be loaded", M.test_common_library_loading)
  run_test("Script files can be loaded", M.test_script_loading)
  run_test("Play state detection works", M.test_play_state_detection)
  run_test("Current position can be retrieved", M.test_current_position)
  run_test("Track counting works", M.test_track_counting)
  run_test("Track access works", M.test_track_access)
  run_test("Marker creation function exists", M.test_marker_creation_function)
  run_test("Action execution function exists", M.test_action_execution_function)
  run_test("Console output works", M.test_console_output)
  run_test("Resource path retrieval works", M.test_resource_path)
  run_test("Project state can be retrieved", M.test_project_state)
  
  reaper.ShowConsoleMsg(string.rep("-", 50) .. "\n")
  reaper.ShowConsoleMsg(string.format("[ReapOBS] Tests Complete: %d passed, %d failed\n", 
    tests_passed, tests_failed))
  
  if tests_failed == 0 then
    reaper.ShowConsoleMsg("[ReapOBS] All integration tests passed!\n")
  else
    reaper.ShowConsoleMsg("[ReapOBS] Some integration tests failed!\n")
  end
end

-- Run tests if this script is executed directly
if reaper then
  M.run()
end

return M
