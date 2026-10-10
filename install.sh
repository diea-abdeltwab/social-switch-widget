#!/usr/bin/env bash
# ============================================================
#  social-switch-widget - one-command installer
#
#    ./install.sh        detects your desktop and installs everything
#
#  1. INSTALL  social-switch + cloudflare-switch + polkit policies,
#              then the GNOME extension (or the Omarchy widget)
#  2. TIDY     removes OLDER copies of the two scripts that would hide the
#              new ones (e.g. in ~/.local/bin or /usr/local/sbin)
#  3. MIGRATE  re-applies your saved blocks with the new script, so nothing
#              you had blocked is lost
#
#  No backup files are created.  Options:
#    --edition gnome|omarchy|core   --yes   --no-cloudflare
#    --prefix DIR   --no-polkit     (the last two are mainly for testing)
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}→${RESET}  $*"; }
ok()      { echo -e "${GREEN}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
die()     { echo -e "${RED}✗${RESET}  $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UUID="social-switch@diea-abdeltwab.github.io"
# sudo searches /usr/local/sbin BEFORE /usr/local/bin and a user's PATH does not list it
SHADOW_DIRS="${SSW_EXTRA_DIRS:-/usr/local/sbin /usr/sbin /sbin}"

EDITION=""; CORE_ARGS=(); PREFIX="/usr/local"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)         CORE_ARGS+=("--yes"); shift ;;
        --edition)        EDITION="${2:?--edition needs gnome, omarchy or core}"; shift 2 ;;
        --no-cloudflare)  CORE_ARGS+=("--no-cloudflare"); shift ;;
        --no-polkit)      CORE_ARGS+=("--no-polkit"); shift ;;
        --prefix)         PREFIX="${2:?--prefix needs a path}"; CORE_ARGS+=("--prefix" "$PREFIX"); shift 2 ;;
        -h|--help)        sed -n '2,19p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$EUID" -ne 0 ] || die "Run this as your normal user, not root - it asks for sudo only where needed."
[ -f "$HERE/core/social-switch" ] || die "core/ not found next to install.sh - run it from the unzipped folder."
command -v sudo >/dev/null || die "sudo is required."

# ── pick the edition ─────────────────────────────────────────────────────────
if [ -z "$EDITION" ]; then
    desktop="${XDG_CURRENT_DESKTOP:-}"
    if [[ "${desktop,,}" == *gnome* ]] || command -v gnome-shell >/dev/null 2>&1; then EDITION="gnome"
    elif command -v omarchy >/dev/null 2>&1 || [ -d "$HOME/.config/omarchy" ]; then EDITION="omarchy"
    else EDITION="core"; fi
fi
case "$EDITION" in gnome|omarchy|core) ;; *) die "unknown edition '$EDITION' (gnome, omarchy, core)";; esac
header "social-switch-widget installer"
info "Edition: $EDITION"
info "Asking for your sudo password once..."
sudo -v

# ── 1. install ───────────────────────────────────────────────────────────────────
header "1/3  Install"
case "$EDITION" in
    gnome)   "$HERE/core/install-core.sh" "${CORE_ARGS[@]}"; "$HERE/gnome/install.sh" --skip-core ;;
    core)    "$HERE/core/install-core.sh" "${CORE_ARGS[@]}" ;;
    omarchy) "$HERE/omarchy-quatto/install.sh" ;;
esac

# ── 2. tidy older copies that would hide the new scripts ──────────────────────────
header "2/3  Tidy"
all_copies() {   # every file that could run when you type the command (user PATH + sudo's sbin dirs)
    local d
    {
        { type -aP "$1" 2>/dev/null || true; }
        for d in $SHADOW_DIRS; do
            if [ -e "$d/$1" ]; then echo "$d/$1"; fi
        done
    } | awk '!seen[$0]++'
}
looks_like_ours() { head -n 25 "$1" 2>/dev/null | grep -qE "social-switch|cloudflare-switch"; }

tidy() {
    local name="$1" dest="$PREFIX/bin/$1" path removed=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ "$(readlink -f "$path")" = "$(readlink -f "$dest")" ] && continue
        if ! looks_like_ours "$path"; then
            warn "$path is named $name but does not look like our script - left alone."
            continue
        fi
        case "$path" in
            "$HOME"/*)    rm -f "$path" && { ok "Removed the old $path (it was hiding the new $name)"; removed=1; } ;;
            /usr/local/*) sudo rm -f "$path" && { ok "Removed the old $path (sudo would have run it instead of the new $name)"; removed=1; } ;;
            *)            warn "Another $name at $path may hide the new one (outside /usr/local and your home, left alone): sudo mv '$path' '$path.old'" ;;
        esac
    done < <(all_copies "$name")
    [ "$removed" -eq 1 ] || true
}
tidy social-switch
if [ -x "$PREFIX/bin/cloudflare-switch" ]; then tidy cloudflare-switch; fi

# ── 3. migrate saved state ───────────────────────────────────────────────────────────
header "3/3  Migrate"
if [ -f /etc/social-switch/blocked ] || [ -f /etc/social-switch/custom ]; then
    info "Re-applying your saved blocks with the new script (nothing you blocked is lost)..."
    if sudo "$PREFIX/bin/social-switch" sync >/dev/null 2>&1; then
        ok "Saved blocks re-applied"
    else
        warn "sync failed - run 'sudo social-switch doctor' to see why"
    fi
else
    ok "Nothing to migrate"
fi
"$PREFIX/bin/social-switch" status 2>/dev/null | sed -n '1,4p' || true

echo
ok "All done."
echo "    Refresh your shell so it finds the new commands:   hash -r"
if [ "$EDITION" = gnome ]; then
    echo "    GNOME: log out and back in once, then enable it in Extensions (or:"
    echo "           gnome-extensions enable $UUID )"
fi
echo "    Clean up leftovers from earlier attempts:            ./cleanup.sh"
