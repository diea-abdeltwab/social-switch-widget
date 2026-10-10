#!/usr/bin/env bash
# ============================================================
#  uninstall.sh — Social Switch (Omarchy 4 "Quattro" / Quickshell)
#  Removes the bar widget, its polkit policy, and optionally
#  the social-switch CLI itself.
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}→${RESET}  $*"; }
success() { echo -e "${GREEN}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✗${RESET}  $*"; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_CFG="$HOME/.config/omarchy"
PLUGIN_DIR="$OMARCHY_CFG/plugins/diea.social-switch"
BACKUP_DIR="$OMARCHY_CFG/.social-switch-backup"
PLUGIN_ID="diea.social-switch"

# ─── Confirm ─────────────────────────────────────────────
echo -e "${BOLD}${RED}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🗑️  Uninstall Social Switch (Omarchy 4) ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  This will:"
echo "  • Disable and remove the bar-widget plugin"
echo "  • Optionally remove the CLI tools, polkit policy and saved state"
echo ""
read -rp "  Are you sure? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { info "Aborted — nothing was changed."; exit 0; }

# ─── Disable + remove the plugin ─────────────────────────
header "🧩 Removing the bar-widget plugin..."

if command -v omarchy &>/dev/null; then
    omarchy plugin disable "$PLUGIN_ID" &>/dev/null || true
    success "Disabled: $PLUGIN_ID"
fi

if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    success "Removed: $PLUGIN_DIR"
else
    info "Plugin directory not found — already removed"
fi

# ─── Optionally remove the CLI tools + polkit policy ─────
echo ""
echo -e "  ${YELLOW}social-switch / cloudflare-switch are standalone CLIs${RESET} - they keep working"
echo -e "  from a terminal with no bar widget involved."
read -rp "  Remove them too (unblocks everything and turns the DNS filter off first)? [y/N] " cli_ans

if [[ "$cli_ans" =~ ^[Yy]$ ]]; then
    header "🗑️  Removing CLI tools, policy and state..."
    "$APP_DIR/../core/uninstall-core.sh"
else
    info "Kept the CLI tools and the polkit policy - only the bar widget is gone"
fi

# ─── Offer backup restore of shell.json ──────────────────
if [ -d "$BACKUP_DIR" ] && ls "$BACKUP_DIR"/shell.json.*.bak &>/dev/null 2>&1; then
    echo ""
    warn "Found a backup of shell.json from before the install:"
    ls -lh "$BACKUP_DIR"/shell.json.*.bak 2>/dev/null | awk '{print "   " $NF " (" $5 ")"}'
    echo ""
    read -rp "  Restore that backup? (usually unnecessary — plugin disable already cleaned up) [y/N] " restore_ans
    if [[ "$restore_ans" =~ ^[Yy]$ ]]; then
        LAST_TS=$(cat "$BACKUP_DIR/last_install.txt" 2>/dev/null || echo "")
        bak="$BACKUP_DIR/shell.json.${LAST_TS}.bak"
        [ -f "$bak" ] || bak=$(ls "$BACKUP_DIR"/shell.json.*.bak 2>/dev/null | sort | tail -1 || echo "")
        if [ -n "$bak" ] && [ -f "$bak" ]; then
            cp "$bak" "$OMARCHY_CFG/shell.json"
            success "Restored: shell.json"
        else
            warn "No backup file found"
        fi
    fi

    echo ""
    read -rp "  Remove the backup folder too? [y/N] " bak_ans
    if [[ "$bak_ans" =~ ^[Yy]$ ]]; then
        rm -rf "$BACKUP_DIR"
        success "Removed: $BACKUP_DIR"
    fi
fi

# ─── Reload the Omarchy shell ────────────────────────────
header "🔄 Reloading the Omarchy shell..."

if command -v omarchy-shell &>/dev/null && omarchy-shell shell reloadConfig &>/dev/null; then
    success "Sent reloadConfig to the running shell"
elif command -v omarchy-restart-shell &>/dev/null; then
    omarchy-restart-shell &>/dev/null || true
    success "Restarted the Omarchy shell"
else
    warn "Could not reload automatically — log out/in to fully clear the widget"
fi

# ─── Summary ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  ✅ Uninstall complete!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo ""
echo -e "  The Omarchy bar has been restored to its original state."
echo ""
