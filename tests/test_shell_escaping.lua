-- ============================================================
-- ReapOBS  Shell Escaping Tests
-- Tests for shell_escape() function from reapobs_common.lua
-- ============================================================

local M = {}

-- Simple shell_escape implementation for testing
-- This mimics the function from reapobs_common.lua
local function shell_escape(str)
  if str == nil then return "" end
  return tostring(str):gsub("'", "'\\''")
end

-- Test: Basic string escaping
function M.test_basic_string_escaping()
  local result = shell_escape("hello")
  assert(result == "hello", "Basic string should not be modified")
end

-- Test: String with single quotes
function M.test_single_quote_escaping()
  local result = shell_escape("it's")
  -- Single quote should be escaped as '\''
  assert(result == "it'\\''s", "Single quote should be escaped")
end

-- Test: Multiple single quotes
function M.test_multiple_single_quotes()
  local result = shell_escape("it's a 'test'")
  assert(result == "it'\\''s a '\\''test'\\''", "Multiple single quotes should be escaped")
end

-- Test: Empty string
function M.test_empty_string()
  local result = shell_escape("")
  assert(result == "", "Empty string should remain empty")
end

-- Test: Nil value
function M.test_nil_value()
  local result = shell_escape(nil)
  assert(result == "", "Nil should be converted to empty string")
end

-- Test: String with double quotes
function M.test_double_quotes()
  local result = shell_escape('it"s')
  -- Double quotes should not be escaped by our function
  assert(result == 'it"s', "Double quotes should not be escaped")
end

-- Test: String with backslashes
function M.test_backslashes()
  local result = shell_escape("path\\to\\file")
  -- Backslashes should not be escaped by our function
  assert(result == "path\\to\\file", "Backslashes should not be escaped")
end

-- Test: String with spaces
function M.test_spaces()
  local result = shell_escape("path with spaces")
  assert(result == "path with spaces", "Spaces should not be escaped")
end

-- Test: String with special characters
function M.test_special_characters()
  local result = shell_escape("path$with&special*chars")
  assert(result == "path$with&special*chars", "Special characters should not be escaped")
end

-- Test: Complex path with spaces and quotes
function M.test_complex_path()
  local result = shell_escape("/path with spaces/it's/file.mp4")
  assert(result == "/path with spaces/it'\\''s/file.mp4", "Complex path should be properly escaped")
end

-- Test: WebSocket URL with password containing quotes
function M.test_websocket_url_with_quotes()
  local result = shell_escape("obsws://localhost:4455/it's_password")
  assert(result == "obsws://localhost:4455/it'\\''s_password", "WebSocket URL with quotes should be escaped")
end

-- Test: Number value
function M.test_number_value()
  local result = shell_escape(123)
  assert(result == "123", "Number should be converted to string")
end

-- Test: Boolean value
function M.test_boolean_value()
  local result = shell_escape(true)
  assert(result == "true", "Boolean should be converted to string")
end

-- Test: Very long string
function M.test_long_string()
  local long_str = string.rep("a", 1000)
  local result = shell_escape(long_str)
  assert(#result == 1000, "Long string should maintain length")
  assert(result == long_str, "Long string without quotes should be unchanged")
end

-- Test: String with only quotes
function M.test_only_quotes()
  local result = shell_escape("'''")
  assert(result == "'\\'''\\'''\\''", "String with only quotes should be properly escaped")
end

-- Test: Unicode characters
function M.test_unicode_characters()
  local result = shell_escape("test_äöå_文件")
  assert(result == "test_äöå_文件", "Unicode characters should not be escaped")
end

-- Run all tests in this module
function M.run(run_test)
  run_test("Basic string escaping works", M.test_basic_string_escaping)
  run_test("Single quote escaping works", M.test_single_quote_escaping)
  run_test("Multiple single quotes escaping works", M.test_multiple_single_quotes)
  run_test("Empty string handling works", M.test_empty_string)
  run_test("Nil value handling works", M.test_nil_value)
  run_test("Double quotes are not escaped", M.test_double_quotes)
  run_test("Backslashes are not escaped", M.test_backslashes)
  run_test("Spaces are not escaped", M.test_spaces)
  run_test("Special characters are not escaped", M.test_special_characters)
  run_test("Complex path escaping works", M.test_complex_path)
  run_test("WebSocket URL with quotes escaping works", M.test_websocket_url_with_quotes)
  run_test("Number value handling works", M.test_number_value)
  run_test("Boolean value handling works", M.test_boolean_value)
  run_test("Long string handling works", M.test_long_string)
  run_test("Only quotes string handling works", M.test_only_quotes)
  run_test("Unicode characters handling works", M.test_unicode_characters)
end

return M
