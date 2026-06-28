-- ============================================================
-- ReapOBS  WebSocket URL Validation Tests
-- Tests for validate_websocket_url() function
-- ============================================================

local M = {}

-- Mock validation function from reapobs_common.lua
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

-- Test: Valid WebSocket URL without password
function M.test_valid_url_no_password()
  local valid, err = validate_websocket_url("obsws://localhost:4455")
  assert(valid == true, "Valid URL without password should pass: " .. tostring(err))
end

-- Test: Valid WebSocket URL with password
function M.test_valid_url_with_password()
  local valid, err = validate_websocket_url("obsws://localhost:4455/mypassword")
  assert(valid == true, "Valid URL with password should pass: " .. tostring(err))
end

-- Test: Valid WebSocket URL with IP address
function M.test_valid_url_with_ip()
  local valid, err = validate_websocket_url("obsws://192.168.1.100:4455")
  assert(valid == true, "Valid URL with IP should pass: " .. tostring(err))
end

-- Test: Valid WebSocket URL with domain
function M.test_valid_url_with_domain()
  local valid, err = validate_websocket_url("obsws://obs.example.com:4455")
  assert(valid == true, "Valid URL with domain should pass: " .. tostring(err))
end

-- Test: Valid WebSocket URL with custom port
function M.test_valid_url_custom_port()
  local valid, err = validate_websocket_url("obsws://localhost:8080")
  assert(valid == true, "Valid URL with custom port should pass: " .. tostring(err))
end

-- Test: Invalid URL - missing protocol
function M.test_invalid_url_missing_protocol()
  local valid, err = validate_websocket_url("localhost:4455")
  assert(valid == false, "URL without protocol should fail")
  assert(err:find("obsws://"), "Error should mention obsws://")
end

-- Test: Invalid URL - wrong protocol
function M.test_invalid_url_wrong_protocol()
  local valid, err = validate_websocket_url("ws://localhost:4455")
  assert(valid == false, "URL with wrong protocol should fail")
  assert(err:find("obsws://"), "Error should mention obsws://")
end

-- Test: Invalid URL - HTTP protocol
function M.test_invalid_url_http_protocol()
  local valid, err = validate_websocket_url("http://localhost:4455")
  assert(valid == false, "URL with HTTP protocol should fail")
end

-- Test: Invalid URL - HTTPS protocol
function M.test_invalid_url_https_protocol()
  local valid, err = validate_websocket_url("https://localhost:4455")
  assert(valid == false, "URL with HTTPS protocol should fail")
end

-- Test: Empty URL
function M.test_empty_url()
  local valid, err = validate_websocket_url("")
  assert(valid == false, "Empty URL should fail")
  assert(err:find("non"), "Error should mention non-empty")
end

-- Test: Nil URL
function M.test_nil_url()
  local valid, err = validate_websocket_url(nil)
  assert(valid == false, "Nil URL should fail")
  assert(err:find("non"), "Error should mention non-empty")
end

-- Test: URL with invalid characters - less than
function M.test_invalid_url_less_than()
  local valid, err = validate_websocket_url("obsws://localhost:4455<password")
  assert(valid == false, "URL with < should fail")
  assert(err:find("invalid characters"), "Error should mention invalid characters")
end

-- Test: URL with invalid characters - greater than
function M.test_invalid_url_greater_than()
  local valid, err = validate_websocket_url("obsws://localhost:4455>password")
  assert(valid == false, "URL with > should fail")
  assert(err:find("invalid characters"), "Error should mention invalid characters")
end

-- Test: URL with invalid characters - double quote
function M.test_invalid_url_double_quote()
  local valid, err = validate_websocket_url('obsws://localhost:4455/pass"word')
  assert(valid == false, "URL with \" should fail")
  assert(err:find("invalid characters"), "Error should mention invalid characters")
end

-- Test: URL with invalid characters - backslash
function M.test_invalid_url_backslash()
  local valid, err = validate_websocket_url("obsws://localhost:4455/pass\\word")
  assert(valid == false, "URL with \\ should fail")
  assert(err:find("invalid characters"), "Error should mention invalid characters")
end

-- Test: URL with single quotes (should be valid)
function M.test_valid_url_with_single_quotes()
  local valid, err = validate_websocket_url("obsws://localhost:4455/it's_password")
  assert(valid == true, "URL with single quotes should be valid: " .. tostring(err))
end

-- Test: URL with spaces (should be valid, handled by shell escaping)
function M.test_valid_url_with_spaces()
  local valid, err = validate_websocket_url("obsws://localhost:4455/my password")
  assert(valid == true, "URL with spaces should be valid: " .. tostring(err))
end

-- Test: URL with special characters (should be valid)
function M.test_valid_url_with_special_chars()
  local valid, err = validate_websocket_url("obsws://localhost:4455/pass-word_123")
  assert(valid == true, "URL with special chars should be valid: " .. tostring(err))
end

-- Test: Very long URL
function M.test_long_url()
  local long_password = string.rep("a", 100)
  local url = "obsws://localhost:4455/" .. long_password
  local valid, err = validate_websocket_url(url)
  assert(valid == true, "Long URL should be valid: " .. tostring(err))
end

-- Test: URL with number type (should fail)
function M.test_invalid_url_number_type()
  local valid, err = validate_websocket_url(12345)
  assert(valid == false, "Number URL should fail")
  assert(err:find("non"), "Error should mention non-empty")
end

-- Test: URL with boolean type (should fail)
function M.test_invalid_url_boolean_type()
  local valid, err = validate_websocket_url(true)
  assert(valid == false, "Boolean URL should fail")
  assert(err:find("non"), "Error should mention non-empty")
end

-- Run all tests in this module
function M.run(run_test)
  run_test("Valid URL without password passes", M.test_valid_url_no_password)
  run_test("Valid URL with password passes", M.test_valid_url_with_password)
  run_test("Valid URL with IP address passes", M.test_valid_url_with_ip)
  run_test("Valid URL with domain passes", M.test_valid_url_with_domain)
  run_test("Valid URL with custom port passes", M.test_valid_url_custom_port)
  run_test("Invalid URL missing protocol fails", M.test_invalid_url_missing_protocol)
  run_test("Invalid URL with wrong protocol fails", M.test_invalid_url_wrong_protocol)
  run_test("Invalid URL with HTTP protocol fails", M.test_invalid_url_http_protocol)
  run_test("Invalid URL with HTTPS protocol fails", M.test_invalid_url_https_protocol)
  run_test("Empty URL fails", M.test_empty_url)
  run_test("Nil URL fails", M.test_nil_url)
  run_test("Invalid URL with < fails", M.test_invalid_url_less_than)
  run_test("Invalid URL with > fails", M.test_invalid_url_greater_than)
  run_test("Invalid URL with double quote fails", M.test_invalid_url_double_quote)
  run_test("Invalid URL with backslash fails", M.test_invalid_url_backslash)
  run_test("Valid URL with single quotes passes", M.test_valid_url_with_single_quotes)
  run_test("Valid URL with spaces passes", M.test_valid_url_with_spaces)
  run_test("Valid URL with special characters passes", M.test_valid_url_with_special_chars)
  run_test("Long URL passes", M.test_long_url)
  run_test("Number type URL fails", M.test_invalid_url_number_type)
  run_test("Boolean type URL fails", M.test_invalid_url_boolean_type)
end

return M
