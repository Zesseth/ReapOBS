-- ============================================================
-- ReapOBS  Test Runner
-- Runs all unit tests for ReapOBS scripts
-- Can be run with standalone Lua 5.3+
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

-- Set up paths for importing test modules
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "."
package.path = package.path .. ";" .. test_dir .. "?.lua"

-- Test results tracking
local tests = {}
local passed = 0
local failed = 0
local total = 0

-- Color output (if terminal supports it)
local function colorize(text, color)
  local colors = {
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    reset = "\27[0m"
  }
  if colors[color] then
    return colors[color] .. text .. colors.reset
  end
  return text
end

-- Test runner function
local function run_test(name, test_func)
  total = total + 1
  local success, err = pcall(test_func)
  
  if success then
    passed = passed + 1
    print(colorize("✓ " .. name, "green"))
    tests[#tests + 1] = {name = name, passed = true}
  else
    failed = failed + 1
    print(colorize("✗ " .. name, "red"))
    print("  Error: " .. tostring(err))
    tests[#tests + 1] = {name = name, passed = false, error = tostring(err)}
  end
end

-- Print summary
local function print_summary()
  print("\n" .. string.rep("=", 50))
  print("Test Summary")
  print(string.rep("=", 50))
  print(string.format("Total:  %d", total))
  print(string.format("Passed: %d", passed))
  print(string.format("Failed: %d", failed))
  
  if failed > 0 then
    print("\nFailed tests:")
    for _, test in ipairs(tests) do
      if not test.passed then
        print(colorize("  - " .. test.name, "red"))
        if test.error then
          print("    " .. test.error)
        end
      end
    end
  end
  
  print(string.rep("=", 50))
  
  if failed == 0 then
    print(colorize("All tests passed!", "green"))
    return true
  else
    print(colorize("Some tests failed!", "red"))
    return false
  end
end

-- Import and run test modules
print("Running ReapOBS Unit Tests...")
print(string.rep("-", 50))

-- Configuration validation tests
local config_tests = require("test_config_validation")
if config_tests and config_tests.run then
  config_tests.run(run_test)
end

-- Shell escaping tests
local shell_tests = require("test_shell_escaping")
if shell_tests and shell_tests.run then
  shell_tests.run(run_test)
end

-- Path handling tests
local path_tests = require("test_path_handling")
if path_tests and path_tests.run then
  path_tests.run(run_test)
end

-- WebSocket validation tests
local ws_tests = require("test_websocket_validation")
if ws_tests and ws_tests.run then
  ws_tests.run(run_test)
end

-- Auto-import logic tests
local auto_import_tests = require("test_auto_import_logic")
if auto_import_tests and auto_import_tests.run then
  auto_import_tests.run(run_test)
end

-- Print summary and exit
local success = print_summary()

if not success then
  os.exit(1)
end
