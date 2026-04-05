#!/bin/bash
# ============================================================
# ReapOBS Installer
# Installs the ReapOBS Lua ReaScripts into REAPER's Scripts
# directory and optionally installs the obs-cmd CLI tool.
#
# Requirements: REAPER (Linux), OBS Studio 28+, curl, tar
# https://github.com/Zesseth/ReapOBS
# License: GNU GPL v2.0
# ============================================================

# ------------------------------------------------------------
# Color helpers
# ------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

info()    { echo -e "${GREEN}[ReapOBS]${NC} $*"; }
warn()    { echo -e "${YELLOW}[ReapOBS WARNING]${NC} $*"; }
error()   { echo -e "${RED}[ReapOBS ERROR]${NC} $*"; }

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
REAPER_SCRIPTS_DIR="$HOME/.config/REAPER/Scripts/ReapOBS"
OBS_CMD_URL="https://github.com/grigio/obs-cmd/releases/latest/download/obs-cmd-x64-linux.tar.gz"
OBS_CMD_INSTALL_DIR="/usr/local/bin"
TMP_DIR=""

# ------------------------------------------------------------
# Cleanup and signal handling
# ------------------------------------------------------------
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT
trap 'echo; warn "Installation cancelled by user."; exit 1' INT

# Resolve the directory this script lives in so it works regardless
# of where it is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------
# Welcome banner
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "          ReapOBS Installer"
echo "============================================"
echo ""

# ------------------------------------------------------------
# Check prerequisites
# ------------------------------------------------------------
info "Checking prerequisites..."

# REAPER config directory
if [ ! -d "$HOME/.config/REAPER" ]; then
  warn "REAPER config directory not found at $HOME/.config/REAPER"
  warn "REAPER may not be installed, or you may not have launched it yet."
  warn "The scripts will still be copied; load them in REAPER when it is installed."
else
  info "REAPER config directory found."
fi

# OBS Studio
if ! command -v obs &>/dev/null; then
  warn "OBS Studio does not appear to be installed (command 'obs' not found)."
  warn "Install OBS Studio v28+ before using ReapOBS."
else
  info "OBS Studio found: $(command -v obs)"
fi

# curl
if ! command -v curl &>/dev/null; then
  error "curl is required but not installed. Install it with: sudo apt install curl"
  exit 1
fi
info "curl found."

# tar
if ! command -v tar &>/dev/null; then
  error "tar is required but not installed. Install it with: sudo apt install tar"
  exit 1
fi
info "tar found."

echo ""

# ------------------------------------------------------------
# obs-cmd installation
# ------------------------------------------------------------
if command -v obs-cmd &>/dev/null; then
  info "obs-cmd is already installed: $(command -v obs-cmd)"
  info "Version: $(obs-cmd --version 2>/dev/null || echo 'unknown')"
else
  warn "obs-cmd is not installed."
  read -p "Would you like to install obs-cmd now? [Y/n] " install_obs_cmd
  install_obs_cmd="${install_obs_cmd:-Y}"

  if [[ "$install_obs_cmd" =~ ^[Yy]$ ]]; then
    echo ""
    info "Downloading obs-cmd from GitHub..."
    TMP_DIR="$(mktemp -d)"
    if ! curl -fsSL "$OBS_CMD_URL" -o "$TMP_DIR/obs-cmd.tar.gz"; then
      error "Failed to download obs-cmd. Check your internet connection."
      exit 1
    fi

    info "Extracting obs-cmd..."
    if ! tar -xzf "$TMP_DIR/obs-cmd.tar.gz" -C "$TMP_DIR"; then
      error "Failed to extract obs-cmd archive."
      exit 1
    fi

    # Find the extracted binary
    OBS_CMD_BIN="$(find "$TMP_DIR" -name "obs-cmd" -type f | head -n1)"
    if [ -z "$OBS_CMD_BIN" ]; then
      error "Could not find obs-cmd binary in the downloaded archive."
      rm -rf "$TMP_DIR"
      exit 1
    fi
    chmod +x "$OBS_CMD_BIN"

    echo ""
    echo "Where would you like to install obs-cmd?"
    echo "  1) $OBS_CMD_INSTALL_DIR/obs-cmd (system-wide, requires sudo)"
    echo "  2) $HOME/.local/bin/obs-cmd (current user only)"
    read -p "Choice [1]: " obs_install_choice
    obs_install_choice="${obs_install_choice:-1}"

    if [ "$obs_install_choice" = "2" ]; then
      DEST="$HOME/.local/bin"
      mkdir -p "$DEST"
      cp "$OBS_CMD_BIN" "$DEST/obs-cmd"
      info "obs-cmd installed to $DEST/obs-cmd"
      if [[ ":$PATH:" != *":$DEST:"* ]]; then
        warn "$DEST is not in your PATH. Add it to your shell profile:"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      fi
    else
      info "Copying obs-cmd to $OBS_CMD_INSTALL_DIR (sudo required)..."
      sudo cp "$OBS_CMD_BIN" "$OBS_CMD_INSTALL_DIR/obs-cmd"
      sudo chmod +x "$OBS_CMD_INSTALL_DIR/obs-cmd"
      info "obs-cmd installed to $OBS_CMD_INSTALL_DIR/obs-cmd"
    fi

    rm -rf "$TMP_DIR"

    # Verify
    if command -v obs-cmd &>/dev/null; then
      info "obs-cmd verified: $(obs-cmd --version 2>/dev/null || echo 'installed successfully')"
    else
      warn "obs-cmd was installed but is not in PATH yet. Open a new terminal or re-source your profile."
    fi
  else
    warn "Skipping obs-cmd installation. You can install it manually later."
    warn "Download from: https://github.com/grigio/obs-cmd/releases"
  fi
fi

echo ""

# ------------------------------------------------------------
# Copy Lua scripts to REAPER's Scripts directory
# ------------------------------------------------------------
info "Creating REAPER scripts directory: $REAPER_SCRIPTS_DIR"
mkdir -p "$REAPER_SCRIPTS_DIR"

SCRIPTS_SRC="$SCRIPT_DIR/scripts"
if [ ! -d "$SCRIPTS_SRC" ]; then
  error "Scripts source directory not found: $SCRIPTS_SRC"
  error "Make sure you are running install.sh from the ReapOBS project root."
  exit 1
fi

for script in \
  reapobs_start_recording.lua \
  reapobs_stop_recording.lua \
  reapobs_toggle_recording.lua; do

  SRC="$SCRIPTS_SRC/$script"
  DEST_FILE="$REAPER_SCRIPTS_DIR/$script"

  if [ ! -f "$SRC" ]; then
    error "Script not found: $SRC"
    exit 1
  fi

  if [ -f "$DEST_FILE" ]; then
    read -p "$script already exists. Overwrite? [y/N] " overwrite
    overwrite="${overwrite:-N}"
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      warn "Skipping $script"
      continue
    fi
  fi

  cp "$SRC" "$DEST_FILE"
  info "Installed: $DEST_FILE"
done

# ------------------------------------------------------------
# Copy toolbar icons to REAPER's toolbar_icons directory
# ------------------------------------------------------------
TOOLBAR_ICONS_DIR="$HOME/.config/REAPER/Data/toolbar_icons"
ICONS_SRC="$SCRIPT_DIR/icons"

if [ -d "$ICONS_SRC" ]; then
  info "Installing toolbar icons..."
  mkdir -p "$TOOLBAR_ICONS_DIR"

  for icon in reapobs_toggle.png; do
    SRC="$ICONS_SRC/$icon"
    DEST_FILE="$TOOLBAR_ICONS_DIR/$icon"

    if [ -f "$SRC" ]; then
      cp "$SRC" "$DEST_FILE"
      info "Installed icon: $DEST_FILE"
    else
      warn "Icon not found: $SRC"
    fi
  done
else
  warn "Icons directory not found: $ICONS_SRC — skipping icon installation."
fi

echo ""

# ------------------------------------------------------------
# Post-install instructions
# ------------------------------------------------------------
echo "============================================"
echo -e "${GREEN}  ReapOBS installation complete!${NC}"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure OBS WebSocket Server:"
echo "   Open OBS Studio → Tools → WebSocket Server Settings"
echo "   Enable the WebSocket Server (default port: 4455)"
echo "   Set or disable authentication as desired"
echo ""
echo "2. Load scripts into REAPER:"
echo "   Open REAPER → Actions → Show Action List"
echo "   Click 'New action...' → 'Load ReaScript...'"
echo "   Navigate to: $REAPER_SCRIPTS_DIR"
echo "   Load all three .lua scripts"
echo ""
echo "3. Assign a keyboard shortcut (recommended):"
echo "   In the Action List, select 'reapobs_toggle_recording'"
echo "   Click 'Add shortcut...' and press e.g. Shift+R"
echo ""
echo "4. Add a toolbar button with the ReapOBS icon (optional):"
echo "   Right-click a toolbar → Customize toolbar..."
echo "   Add the ReapOBS toggle action"
echo "   Click the icon area (bottom left) → select 'reapobs_toggle'"
echo ""
echo "5. Configure the scripts (optional):"
echo "   Edit any .lua file in $REAPER_SCRIPTS_DIR"
echo "   Adjust OBS_CMD_PATH, OBS_WEBSOCKET_URL, and other settings"
echo "   at the top of each script."
echo ""
echo "6. Arm tracks in REAPER for recording, then use your shortcut!"
echo ""
info "For help and documentation, visit: https://github.com/Zesseth/ReapOBS"
echo ""
