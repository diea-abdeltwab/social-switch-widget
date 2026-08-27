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

OMARCHY_CFG="$HOME/.config/omarchy"
PLUGIN_DIR="$OMARCHY_CFG/plugins/diea.social-switch"
BACKUP_DIR="$OMARCHY_CFG/.social-switch-backup"
PLUGIN_ID="diea.social-switch"
SCRIPT_DEST="/usr/local/bin/social-switch"
POLKIT_DEST="/usr/share/polkit-1/actions/com.diea.socialswitch.policy"

# ─── Confirm ─────────────────────────────────────────────
echo -e "${BOLD}${RED}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🗑️  Uninstall Social Switch (Omarchy 4) ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  This will:"
echo "  • Disable and remove the bar-widget plugin"
echo "  • Remove the polkit privilege policy"
echo "  • Optionally remove the social-switch CLI script and its state"
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

# ─── Remove the polkit policy ────────────────────────────
header "🔐 Removing polkit policy..."

if [ -f "$POLKIT_DEST" ]; then
    sudo rm -f "$POLKIT_DEST"
    success "Removed: $POLKIT_DEST"
else
    info "Polkit policy not found — already removed"
fi

# ─── Optionally remove the CLI script + its state ────────
echo ""
echo -e "  ${YELLOW}social-switch is also a standalone CLI${RESET} — sudo social-switch on/off works"
echo -e "  from a terminal with no bar widget involved."
read -rp "  Remove it too (and /etc/social-switch/ state + backup /etc/hosts)? [y/N] " cli_ans

if [[ "$cli_ans" =~ ^[Yy]$ ]]; then
    header "🗑️  Removing CLI and state..."

    if [ -x "$SCRIPT_DEST" ]; then
        current_state="$("$SCRIPT_DEST" status --json 2>/dev/null | grep -o '"state":"[a-z]*"' | cut -d'"' -f4 || echo "")"
        if [ "$current_state" = "off" ]; then
            warn "Blocking is currently ON — unblocking before removing the CLI"
            sudo "$SCRIPT_DEST" on || warn "Could not auto-unblock — you may need to restore /etc/hosts.bak manually"
        fi
        sudo rm -f "$SCRIPT_DEST"
        success "Removed: $SCRIPT_DEST"
    fi

    if [ -d /etc/social-switch ]; then
        sudo rm -rf /etc/social-switch
        success "Removed: /etc/social-switch/"
    fi
else
    info "Kept $SCRIPT_DEST — the CLI still works standalone, only the bar widget is gone"
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
