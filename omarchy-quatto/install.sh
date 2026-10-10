#!/usr/bin/env bash
# ============================================================
#  install.sh — Social Switch (Omarchy 4 "Quattro" / Quickshell)
#  Installs the shared CLI tools (../core: social-switch + cloudflare-switch),
#  the polkit privilege policy, and a Quickshell bar-widget popup panel.
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
CORE_DIR="$APP_DIR/../core"
OMARCHY_CFG="$HOME/.config/omarchy"
SHELL_JSON="$OMARCHY_CFG/shell.json"
PLUGIN_DIR="$OMARCHY_CFG/plugins/diea.social-switch"
BACKUP_DIR="$OMARCHY_CFG/.social-switch-backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

PLUGIN_ID="diea.social-switch"
SCRIPT_DEST="/usr/local/bin/social-switch"
POLKIT_DEST="/usr/share/polkit-1/actions/com.diea.socialswitch.policy"

[ -f "$CORE_DIR/social-switch" ] || { error "../core not found - run this from a full clone of the repository."; exit 1; }

# ─── 0. Sanity check: is this actually Omarchy 4? ────────
header "🔎 Checking this looks like Omarchy 4 (Quattro)..."

if [ -d "$HOME/.config/waybar" ] && [ ! -f "$SHELL_JSON" ] && ! command -v omarchy &>/dev/null; then
    warn "Found ~/.config/waybar but no shell.json/omarchy CLI — this looks like Omarchy 3."
    read -rp "  Continue anyway? [y/N] " force_ans
    [[ "$force_ans" =~ ^[Yy]$ ]] || { error "Aborted."; exit 1; }
fi
success "Proceeding with the Omarchy 4 / Quickshell install"

# ─── 1. Check dependencies ───────────────────────────────
header "🔍 Checking dependencies..."

check_cmd() {
    local cmd=$1 pkg=$2
    if command -v "$cmd" &>/dev/null; then
        success "$cmd found"
    else
        warn "$cmd not found — install: $pkg"
        MISSING+=("$pkg")
    fi
}

MISSING=()
check_cmd bash    "bash"
check_cmd pkexec  "polkit"
check_cmd awk     "gawk"
check_cmd grep    "grep"

if [ -d /usr/share/polkit-1/actions ]; then
    success "polkit action directory found"
else
    warn "/usr/share/polkit-1/actions not found — is polkit installed?"
    MISSING+=("polkit")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    warn "Missing packages: ${MISSING[*]}"
    if command -v pacman &>/dev/null; then echo -e "    ${YELLOW}sudo pacman -S ${MISSING[*]}${RESET}"
    else echo -e "    ${YELLOW}install: ${MISSING[*]}${RESET}"; fi
    echo ""
    read -rp "Continue anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { error "Aborted."; exit 1; }
fi

# ─── 2. Backup anything we're about to overwrite ─────────
header "💾 Backing up anything we're about to overwrite..."

mkdir -p "$BACKUP_DIR"

if [ -f "$SHELL_JSON" ]; then
    cp "$SHELL_JSON" "$BACKUP_DIR/shell.json.${TIMESTAMP}.bak"
    success "Backed up: shell.json (bar placement below is done via 'omarchy bar move', but a raw backup costs nothing)"
else
    info "No existing shell.json — Omarchy will seed one from its own defaults"
fi

echo "$TIMESTAMP" > "$BACKUP_DIR/last_install.txt"
success "Backup saved to: $BACKUP_DIR"

# ─── 2b. Bar placement preference ────────────────────────
header "📍 Where should the icon go?"

BAR_SECTION="right"
echo -e "  Which bar section should Social Switch live in?"
echo -e "    ${CYAN}1)${RESET} right   (default — next to network/audio/power)"
echo -e "    ${CYAN}2)${RESET} center"
echo -e "    ${CYAN}3)${RESET} left"
read -rp "  Choice [1/2/3, default 1]: " section_choice
case "$section_choice" in
    2) BAR_SECTION="center" ;;
    3) BAR_SECTION="left" ;;
    *) BAR_SECTION="right" ;;
esac
success "Bar section set to: $BAR_SECTION"

# ─── 3+4. Shared CLI tools + polkit policy (single source: ../core) ─
# One copy of social-switch for every front end, so the widget can never
# overwrite a newer script you installed by hand with an older bundled one.
# The installer backs up whatever it replaces and refuses silent downgrades.
header "📁 Installing the CLI tools and polkit policy..."

"$CORE_DIR/install-core.sh"

# ─── 5. Install the Quickshell plugin ────────────────────
header "🧩 Installing the Quickshell bar-widget plugin..."

# Wipe first, don't just copy over — a stale file left behind from an
# earlier version of this plugin (different filename, different case)
# sitting alongside the new ones is exactly what trips Quickshell's
# "File name case mismatch" loader error. A clean directory guarantees
# there's nothing old for the new files to collide with.
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$APP_DIR/plugin/manifest.json" "$APP_DIR/plugin/Widget.qml" "$APP_DIR/plugin/Panel.qml" "$PLUGIN_DIR/"
success "Plugin files → $PLUGIN_DIR (directory wiped first)"

# ─── 5b. Validate before enabling ────────────────────────
header "🩺 Validating the plugin..."

if command -v omarchy &>/dev/null; then
    if omarchy plugin validate "$PLUGIN_DIR"; then
        success "Manifest and folder layout are valid"
    else
        error "Plugin failed validation — see message above"
        exit 1
    fi
fi

if command -v qmllint &>/dev/null && [ -n "${OMARCHY_PATH:-}" ]; then
    if qmllint -I "$OMARCHY_PATH/shell" "$PLUGIN_DIR/Widget.qml" "$PLUGIN_DIR/Panel.qml"; then
        success "qmllint: no issues found"
    else
        warn "qmllint reported issues — see above (may still load; check before relying on it)"
    fi
else
    info "qmllint not available or \$OMARCHY_PATH unset — skipping QML lint (not fatal)"
fi

# ─── 6. Enable + place on the bar ────────────────────────
header "⚙️  Enabling the plugin and placing it on the bar..."

if command -v omarchy-shell &>/dev/null; then
    omarchy-shell shell rescanPlugins &>/dev/null || warn "rescanPlugins IPC call failed — continuing anyway"
fi

if command -v omarchy &>/dev/null; then
    if omarchy plugin enable "$PLUGIN_ID" &>/dev/null; then
        success "Enabled plugin: $PLUGIN_ID"
    else
        warn "Could not enable via 'omarchy plugin enable' — enable it from Setup > Plugins instead"
    fi

    if omarchy bar move "$PLUGIN_ID" "$BAR_SECTION" &>/dev/null; then
        success "Placed on bar: $BAR_SECTION"
    else
        warn "Could not place automatically — drag it into place from the bar, or run:"
        echo -e "    ${CYAN}omarchy bar move $PLUGIN_ID $BAR_SECTION${RESET}"
    fi
else
    warn "'omarchy' CLI not found — add the widget manually:"
    echo -e "    Setup > Plugins > Enable > $PLUGIN_ID"
fi

# ─── 7. Reload the Omarchy shell ─────────────────────────
header "🔄 Reloading the Omarchy shell..."

if command -v omarchy-shell &>/dev/null && omarchy-shell shell reloadConfig &>/dev/null; then
    success "Sent reloadConfig to the running shell (shell.json re-read live)"
elif command -v omarchy-restart-shell &>/dev/null; then
    omarchy-restart-shell &>/dev/null || true
    success "Restarted the Omarchy shell (omarchy-restart-shell)"
else
    warn "Could not reload automatically — log out/in, or run:"
    echo -e "    ${CYAN}omarchy-shell shell reloadConfig${RESET}   (live reload)"
    echo -e "    ${CYAN}omarchy-restart-shell${RESET}              (full shell restart)"
fi

# ─── 8. Quick test ────────────────────────────────────────
header "🧪 Testing the CLI (no root needed for this part)..."

if output=$("$SCRIPT_DEST" status --json 2>/dev/null) && echo "$output" | grep -q '"platforms"'; then
    success "social-switch status --json responds correctly"
else
    warn "Unexpected output from '$SCRIPT_DEST status --json' — check it manually"
fi

# ─── Summary ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  ✅ Installation complete!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${CYAN}Files installed:${RESET}"
echo -e "    $SCRIPT_DEST   (+ cloudflare-switch)"
echo -e "    $POLKIT_DEST"
echo -e "    $PLUGIN_DIR/{manifest.json,Widget.qml,Panel.qml}"
echo ""
echo -e "  ${CYAN}Bar placement:${RESET}"
echo -e "    $BAR_SECTION  (move anytime: drag the icon, or 'omarchy bar move $PLUGIN_ID <section>')"
echo ""
echo -e "  ${CYAN}Backup saved at:${RESET}"
echo -e "    $BACKUP_DIR/"
echo ""
echo -e "  ${YELLOW}Every toggle asks for your password via polkit — that's intentional,${RESET}"
echo -e "  ${YELLOW}see README → 'Privilege model' if you'd rather understand why before using it.${RESET}"
echo ""
echo -e "  ${YELLOW}To uninstall:${RESET}"
echo -e "    ./uninstall.sh"
echo ""
echo -e "  ${CYAN}If the icon doesn't appear or the popup stays empty:${RESET}"
echo -e "    qs log -p \"\$OMARCHY_PATH/shell\" --tail 100    # real QML errors, not journalctl"
echo ""
