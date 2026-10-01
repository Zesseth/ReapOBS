#!/bin/bash
# ============================================================
# ReapOBS – Local test runner
# Runs all automated checks that need no REAPER or OBS:
#   1. Lua interpreter and version check (5.3/5.4)
#   2. Syntax check (luac -p) for every script and test file
#   3. Regression test suite with mock REAPER API and stub binaries
# Usage: ./run_tests.sh
# https://github.com/Zesseth/ReapOBS
# License: GNU GPL v2.0
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

FAILED=0

# Always run from the repository root, so the script works when
# invoked from any directory or with an absolute path
cd "$(dirname "$0")" || exit 1

# ------------------------------------------------------------
# 1. Find a suitable Lua interpreter
# ------------------------------------------------------------
LUA=""
LUAC=""
for v in lua5.3 lua5.4 lua; do
  if command -v "$v" >/dev/null 2>&1; then
    LUA="$v"
    LUAC="${v/luac/luac}"
    case "$v" in
      lua5.3) LUAC=luac5.3 ;;
      lua5.4) LUAC=luac5.4 ;;
      lua)    LUAC=luac ;;
    esac
    break
  fi
done

if [ -z "$LUA" ]; then
  fail "No Lua interpreter found. Install one with: sudo apt install lua5.3"
  exit 1
fi
info "Using interpreter: $LUA"

# ------------------------------------------------------------
# 2. Syntax check all Lua sources
# ------------------------------------------------------------
if command -v "$LUAC" >/dev/null 2>&1 || [ -x "$(command -v "$LUAC" 2>/dev/null)" ]; then
  SYNTAX_OK=1
  for f in scripts/*.lua tests/*.lua; do
    if ! "$LUAC" -p "$f" 2>/dev/null; then
      fail "Syntax error in $f"
      "$LUAC" -p "$f"
      SYNTAX_OK=0
    fi
  done
  if [ "$SYNTAX_OK" -eq 1 ]; then
    pass "Syntax check OK (scripts/*.lua tests/*.lua)"
  else
    FAILED=1
  fi
else
  info "luac not found – skipping syntax check (tests still run)"
fi

# ------------------------------------------------------------
# 3. Run the regression test suite
# ------------------------------------------------------------
if "$LUA" tests/test_bug_regressions.lua; then
  pass "Regression test suite passed"
else
  fail "Regression test suite FAILED"
  FAILED=1
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "------------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
else
  echo -e "${RED}Some checks failed.${NC}"
  exit 1
fi
