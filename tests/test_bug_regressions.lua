-- ============================================================
-- ReapOBS – Bug Regression Tests
-- Regression tests for GitHub issues #10 and #11, plus a
-- smoke test of the full start/stop/auto-import chain using
-- the mock REAPER API and stub binaries.
-- Run standalone: lua5.3 tests/test_bug_regressions.lua
-- License: GNU GPL v2.0
-- ============================================================

local tests_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = package.path .. ";" .. tests_dir .. "?.lua"

local MockReaper = require("mock_reaper")

local script_dir = tests_dir .. "../scripts/"
local repo_root = tests_dir .. ".."

-- ------------------------------------------------------------
-- Test harness
-- ------------------------------------------------------------
local passed, failed = 0, 0
local function run_test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name)
    print("    Error: " .. tostring(err))
  end
end

-- ------------------------------------------------------------
-- Helpers: set up sandboxed script environment
-- ------------------------------------------------------------
local function make_stub_bin(dir, name, script)
  os.execute("mkdir -p '" .. dir .. "'")
  local path = dir .. "/" .. name
  local f = assert(io.open(path, "w"))
  f:write(script)
  f:close()
  os.execute("chmod +x '" .. path .. "'")
  return path
end

local function make_sandbox()
  local base = "/tmp/reapobs-tests-" .. tostring(math.floor(os.clock() * 1000000))
  os.execute("mkdir -p '" .. base .. "/Scripts/ReapOBS'")
  os.execute("mkdir -p '" .. base .. "/VideoRecording'")
  os.execute("cp '" .. repo_root .. "/scripts/'*.lua '" .. base .. "/Scripts/ReapOBS/'")
  -- Patch config to point at the sandbox
  local cfg_path = base .. "/Scripts/ReapOBS/reapobs_config.lua"
  local f = assert(io.open(cfg_path, "r"))
  local cfg = f:read("*a")
  f:close()
  cfg = cfg:gsub('OBS_CMD_PATH = "[^"]*"', 'OBS_CMD_PATH = "' .. base .. '/bin/obs-cmd"')
  cfg = cfg:gsub('FFMPEG_PATH = "[^"]*"', 'FFMPEG_PATH = "' .. base .. '/bin/ffmpeg"')
  cfg = cfg:gsub('OBS_OUTPUT_DIR = "[^"]*"', 'OBS_OUTPUT_DIR = "' .. base .. '/VideoRecording"')
  cfg = cfg:gsub('DEBUG = false', 'DEBUG = true')
  -- Tests that assert immediate start run with the countdown disabled
  cfg = cfg:gsub('COUNTDOWN_SECONDS = 5', 'COUNTDOWN_SECONDS = 0')
  local f2 = assert(io.open(cfg_path, "w"))
  f2:write(cfg)
  f2:close()
  return base
end

local function load_script(base, mock, name)
  -- REAPER exposes the API as a real global; do the same for the mock
  reaper = mock:api()
  local chunk = assert(loadfile(base .. "/Scripts/ReapOBS/" .. name))
  chunk()
end

-- ------------------------------------------------------------
-- Issue #10: REC STOP marker must land at the real stop position
-- ------------------------------------------------------------
local function test_stop_marker_position()
  local base = make_sandbox()
  make_stub_bin(base .. "/bin", "obs-cmd", "#!/bin/sh\nexit 0\n")
  make_stub_bin(base .. "/bin", "ffmpeg",
    "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in /tmp/*) echo stub > \"$a\";; esac; done\nexit 0\n")

  local mock = MockReaper.new{resource_path = base}
  -- Simulate: recording in progress, playhead at 42.0
  mock.playstate = 5
  mock.playpos = 42.0

  load_script(base, mock, "reapobs_stop_recording.lua")

  local stop_markers = {}
  for _, m in ipairs(mock.markers) do
    if m.name and m.name:sub(1, #"REC STOP") == "REC STOP" then
      stop_markers[#stop_markers + 1] = m
    end
  end
  assert(#stop_markers == 1, "expected exactly one REC STOP marker, got " .. #stop_markers)
  assert(stop_markers[1].pos == 42.0,
    "REC STOP marker should be at 42.0 (real stop position), got " .. tostring(stop_markers[1].pos))
end

-- ------------------------------------------------------------
-- Issue #11: no raw control characters in any text file
-- ------------------------------------------------------------
local function test_no_control_chars()
  local files = {
    "scripts/reapobs_common.lua",
    "scripts/reapobs_config.lua",
    "scripts/reapobs_start_recording.lua",
    "scripts/reapobs_stop_recording.lua",
    "scripts/reapobs_toggle_recording.lua",
    "scripts/reapobs_countdown.lua",
    "install.sh",
    "README.md",
  }
  for _, rel in ipairs(files) do
    local path = repo_root .. "/" .. rel
    local f = io.open(path, "rb")
    assert(f, "missing file: " .. path)
    local data = f:read("*a")
    f:close()
    -- Allow tab, LF, CR; reject other C0 control characters
    local bad = {}
    for i = 1, #data do
      local b = data:byte(i)
      if b < 32 and b ~= 9 and b ~= 10 and b ~= 13 then
        bad[#bad + 1] = string.format("%s: byte 0x%02X", rel, b)
      end
    end
    assert(#bad == 0, "control characters remain in: " .. table.concat(bad, ", "))
  end
end

-- ------------------------------------------------------------
-- Smoke: full start → stop → auto-import chain with stubs
-- ------------------------------------------------------------
local function test_full_chain_smoke()
  local base = make_sandbox()
  make_stub_bin(base .. "/bin", "obs-cmd", "#!/bin/sh\nexit 0\n")
  make_stub_bin(base .. "/bin", "ffmpeg",
    "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in /tmp/*) echo stub > \"$a\";; esac; done\nexit 0\n")

  -- A "recent" recording file, modified 2 minutes ago
  local video = base .. "/VideoRecording/take-01.mp4"
  local f = assert(io.open(video, "w"))
  f:write("fake video data")
  f:close()
  os.execute("touch -d '2 minutes ago' '" .. video .. "'")

  -- START: not recording initially
  local mock = MockReaper.new{resource_path = base}
  mock.editcur = 30.0
  load_script(base, mock, "reapobs_toggle_recording.lua")
  assert(mock.playstate == 5, "REAPER should be recording after start")
  assert(#mock.commands > 0 and mock.commands[#mock.commands] == 1013,
    "record command 1013 should have been issued")

  -- Simulate some recording time passing
  mock.playpos = 72.0

  -- STOP
  load_script(base, mock, "reapobs_toggle_recording.lua")
  assert(mock.playstate == 1, "REAPER transport should be stopped after stop")

  -- Auto-import: "Videos" folder with a child track must exist and contain the item
  local videos_track_idx = nil
  for i, t in ipairs(mock.tracks) do
    if t.name == "Videos" then videos_track_idx = i end
  end
  assert(videos_track_idx, "Videos bus track should have been created")
  local child = mock.tracks[videos_track_idx + 1]
  assert(child, "a child track under Videos should exist")
  assert(#child.items == 1, "child track should contain the imported video item")
  assert(child.items[1].path == video,
    "imported item should be the latest video, got: " .. tostring(child.items[1].path))
end

-- ------------------------------------------------------------
-- Toggle state: toolbar toggle must follow the recording state
-- ------------------------------------------------------------
local function test_toggle_state_tracking()
  local base = make_sandbox()
  make_stub_bin(base .. "/bin", "obs-cmd", "#!/bin/sh\nexit 0\n")

  make_stub_bin(base .. "/bin", "ffmpeg", "#!/bin/sh\nexit 0\n")

  local mock = MockReaper.new{resource_path = base}
  load_script(base, mock, "reapobs_toggle_recording.lua")
  assert(mock.toggle_state == 1, "toggle state should be 1 while recording")

  mock.playpos = 10.0
  load_script(base, mock, "reapobs_toggle_recording.lua")
  assert(mock.toggle_state == 0, "toggle state should be 0 after stopping")
end

-- ------------------------------------------------------------
-- Start guard: if OBS connection fails and REQUIRE_OBS, no recording
-- ------------------------------------------------------------
local function test_start_guard_obs_required()
  local base = make_sandbox()
  -- obs-cmd stub that always fails (simulates OBS not running)
  make_stub_bin(base .. "/bin", "obs-cmd", "#!/bin/sh\necho 'WebSocket connection failed' >&2\nexit 1\n")
  make_stub_bin(base .. "/bin", "ffmpeg", "#!/bin/sh\nexit 0\n")

  local mock = MockReaper.new{resource_path = base}
  load_script(base, mock, "reapobs_toggle_recording.lua")
  assert(mock.playstate ~= 5, "recording must not start when OBS is required and unreachable")
  assert(#mock.msgbox_log > 0, "a dialog should inform the user about the failure")
end

-- ------------------------------------------------------------
-- Issue #3: configurable countdown before recording starts
-- ------------------------------------------------------------
local function make_countdown_sandbox()
  local base = make_sandbox()
  make_stub_bin(base .. "/bin", "obs-cmd", "#!/bin/sh\nexit 0\n")
  make_stub_bin(base .. "/bin", "ffmpeg", "#!/bin/sh\nexit 0\n")
  -- COUNTDOWN_SECONDS = 0: current behavior, start immediately
  local cfg_path = base .. "/Scripts/ReapOBS/reapobs_config.lua"
  local f = assert(io.open(cfg_path, "r"))
  local cfg = f:read("*a")
  f:close()
  cfg = cfg:gsub("COUNTDOWN_SECONDS = 5", "COUNTDOWN_SECONDS = 0")
  local f2 = assert(io.open(cfg_path, "w"))
  f2:write(cfg)
  f2:close()
  return base
end

local function test_countdown_zero_starts_immediately()
  local base = make_countdown_sandbox()
  local mock = MockReaper.new{resource_path = base}
  mock.gfx_keys = {}
  -- Replace global gfx with the mock so the countdown module uses it
  gfx = mock:gfx_api()
  load_script(base, mock, "reapobs_start_recording.lua")
  assert(mock.playstate == 5, "COUNTDOWN_SECONDS = 0 must start recording immediately")
  assert(#mock.defer_queue == 0, "no deferred loop should be queued")
end

local function make_countdown_sandbox_5()
  local base = make_countdown_sandbox()
  local cfg_path = base .. "/Scripts/ReapOBS/reapobs_config.lua"
  local f = assert(io.open(cfg_path, "r"))
  local cfg = f:read("*a")
  f:close()
  cfg = cfg:gsub("COUNTDOWN_SECONDS = 0", "COUNTDOWN_SECONDS = 5")
  local f2 = assert(io.open(cfg_path, "w"))
  f2:write(cfg)
  f2:close()
  return base
end

local function test_countdown_starts_after_delay()
  local base = make_countdown_sandbox_5()
  local mock = MockReaper.new{resource_path = base}
  gfx = mock:gfx_api()
  load_script(base, mock, "reapobs_start_recording.lua")
  assert(mock.playstate ~= 5, "recording must not start before the countdown finishes")
  assert(mock.gfx_state and mock.gfx_state.open == true, "countdown window should be open")
  -- Countdown not finished yet: numbers drawn, no recording
  mock:run_deferred(5)
  assert(mock.playstate ~= 5, "recording must not start mid-countdown")
  -- Countdown finished: recording starts and REC is shown
  mock:advance(6)
  mock:run_deferred(20)
  assert(mock.playstate == 5, "recording must start after the countdown finishes")
  local drew_rec = false
  for _, s in ipairs(mock.gfx_drawn) do
    if s:find("REC") then drew_rec = true end
  end
  assert(drew_rec, "REC indicator must be drawn when recording starts")
  -- Auto-close after COUNTDOWN_AUTO_CLOSE seconds
  mock:advance(3)
  mock:run_deferred(10)
  assert(mock.gfx_quit, "countdown window must auto-close after recording starts")
end

local function test_countdown_esc_aborts()
  local base = make_countdown_sandbox_5()
  local mock = MockReaper.new{resource_path = base}
  gfx = mock:gfx_api()
  load_script(base, mock, "reapobs_start_recording.lua")
  assert(mock.playstate ~= 5, "recording must not start before the countdown finishes")
  -- Press ESC during the countdown
  mock.gfx_keys = {27}
  mock:run_deferred(3)
  assert(mock.playstate ~= 5, "ESC must abort without starting recording")
  assert(mock.gfx_quit, "countdown window must close on ESC")
end

print("============================================================")
print("ReapOBS bug regression tests")
print("============================================================")
run_test("Issue #10: REC STOP marker at real stop position", test_stop_marker_position)
run_test("Issue #11: no raw control characters in files", test_no_control_chars)
run_test("Full chain smoke: start → stop → auto-import", test_full_chain_smoke)
run_test("Toolbar toggle state follows recording state", test_toggle_state_tracking)
run_test("Start guard: OBS required, no recording on failure", test_start_guard_obs_required)
run_test("Issue #3: COUNTDOWN_SECONDS = 0 starts immediately", test_countdown_zero_starts_immediately)
run_test("Issue #3: countdown starts recording after delay, shows REC, auto-closes", test_countdown_starts_after_delay)
run_test("Issue #3: ESC aborts countdown without recording", test_countdown_esc_aborts)

print("------------------------------------------------------------")
print(string.format("Total: %d  Passed: %d  Failed: %d", passed + failed, passed, failed))
print("------------------------------------------------------------")
if failed > 0 then os.exit(1) end
