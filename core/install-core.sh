#!/usr/bin/env bash
# ============================================================
#  install-core.sh - installs the shared command-line tools
#    * social-switch      (blocks social media via /etc/hosts)
#    * cloudflare-switch  (Cloudflare DNS filter on/off)
#    * polkit policies    (let a desktop widget run the tools with a GUI password prompt)
#  Used by install.sh, gnome/install.sh and omarchy-quatto/install.sh; fine on its own too.
#
#  Usage: ./install-core.sh [--prefix /usr/local] [--no-cloudflare] [--no-polkit] [--yes]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}→${RESET}  $*"; }
success() { echo -e "${GREEN}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✗${RESET}  $*"; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/usr/local"
WITH_CLOUDFLARE=1
WITH_POLKIT=1
ASSUME_YES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)         PREFIX="${2:?--prefix needs a path}"; shift 2 ;;
        --no-cloudflare)  WITH_CLOUDFLARE=0; shift ;;
        --no-polkit)      WITH_POLKIT=0; shift ;;
        --yes|-y)         ASSUME_YES=1; shift ;;
        -h|--help)        sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) error "unknown option: $1"; exit 1 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
POLKIT_DIR="/usr/share/polkit-1/actions"
SS_DEST="$BIN_DIR/social-switch"
CF_DEST="$BIN_DIR/cloudflare-switch"
POLICY_DEST="$POLKIT_DIR/com.diea.socialswitch.policy"
CF_POLICY_DEST="$POLKIT_DIR/com.diea.cloudflareswitch.policy"

ask() {   # ask "question"  -> 0 on yes
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local a; read -rp "  $1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]
}

pkg_hint() {   # print the right install command for this distro
    local pkgs="$*"
    if   command -v dnf     >/dev/null; then echo "sudo dnf install $pkgs"
    elif command -v apt-get >/dev/null; then echo "sudo apt install $pkgs"
    elif command -v pacman  >/dev/null; then echo "sudo pacman -S $pkgs"
    elif command -v zypper  >/dev/null; then echo "sudo zypper install $pkgs"
    elif command -v apk     >/dev/null; then echo "sudo apk add $pkgs"
    elif command -v xbps-install >/dev/null; then echo "sudo xbps-install $pkgs"
    else echo "(install: $pkgs)"; fi
}

script_version() { sed -n 's/^VERSION="\([0-9.]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1; }
# true if $1 is a strictly newer version than $2
version_gt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }

install_tool() {   # install_tool NAME SRC DEST
    local name="$1" src="$2" dest="$3" new old
    new="$(script_version "$src")"
    if [ -f "$dest" ]; then
        old="$(script_version "$dest")"
        if [ -n "$old" ] && [ -n "$new" ] && version_gt "$old" "$new"; then
            warn "$dest is v$old, newer than the bundled v$new."
            ask "Overwrite it with v$new anyway?" || { info "Kept $dest"; return 0; }
        fi
        info "Replacing $name v${old:-?}"
    fi
    sudo install -D -m 0755 "$src" "$dest"
    success "$name v$new -> $dest"
}

header "Checking dependencies..."
MISSING=()
for pair in "bash:bash" "awk:gawk" "flock:util-linux" "getent:glibc-common" "sudo:sudo"; do
    cmd="${pair%%:*}"; pkg="${pair##*:}"
    if command -v "$cmd" >/dev/null; then success "$cmd"; else warn "$cmd missing"; MISSING+=("$pkg"); fi
done
if [ "$WITH_POLKIT" -eq 1 ]; then
    if command -v pkexec >/dev/null; then success "pkexec"; else warn "pkexec missing (needed by desktop widgets)"; MISSING+=("polkit"); fi
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    error "bash >= 4.4 is required (found $BASH_VERSION)"; exit 1
fi
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "    $(pkg_hint "${MISSING[@]}")"
    ask "Continue anyway?" || { error "Aborted."; exit 1; }
fi

header "Installing command-line tools..."
install_tool social-switch "$CORE_DIR/social-switch" "$SS_DEST"
if [ "$WITH_CLOUDFLARE" -eq 1 ]; then
    install_tool cloudflare-switch "$CORE_DIR/cloudflare-switch" "$CF_DEST"
fi

if [ "$WITH_POLKIT" -eq 1 ]; then
    header "Installing polkit policy..."
    if [ ! -d "$POLKIT_DIR" ]; then
        warn "$POLKIT_DIR not found - polkit missing, or an immutable distro (Silverblue/Kinoite)."
        warn "Skipping the policy: widgets will not be able to ask for a password."
    else
        tmp="$(mktemp)"
        # The policy matches the script by absolute path, so follow --prefix.
        sed "s|/usr/local/bin/social-switch|$SS_DEST|" "$CORE_DIR/polkit/com.diea.socialswitch.policy" > "$tmp"
        sudo install -m 0644 "$tmp" "$POLICY_DEST"
        rm -f "$tmp"
        success "polkit action -> $POLICY_DEST"
        if [ "$WITH_CLOUDFLARE" -eq 1 ]; then
            tmp="$(mktemp)"
            sed "s|/usr/local/bin/cloudflare-switch|$CF_DEST|" "$CORE_DIR/polkit/com.diea.cloudflareswitch.policy" > "$tmp"
            sudo install -m 0644 "$tmp" "$CF_POLICY_DEST"
            rm -f "$tmp"
            success "polkit action -> $CF_POLICY_DEST"
        fi
    fi
fi

header "Sanity test (no root needed)..."
if out="$("$SS_DEST" status --json 2>/dev/null)" && grep -q '"platforms"' <<<"$out"; then
    success "social-switch status --json works"
else
    warn "unexpected output from '$SS_DEST status --json' - run it by hand to see why"
fi
if [ "$WITH_CLOUDFLARE" -eq 1 ] && "$CF_DEST" status --short >/dev/null 2>&1; then
    success "cloudflare-switch status works ($("$CF_DEST" status --short))"
fi
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in your PATH" ;; esac

# An older copy earlier in PATH (e.g. ~/.local/bin) would silently win when you
# type the command, while desktop widgets use the installed one - two versions.
# sudo's secure_path (Fedora, RHEL) searches /usr/local/sbin BEFORE /usr/local/bin,
# and a normal user's PATH does not list it - so look there explicitly as well.
SHADOW_DIRS="${SSW_EXTRA_DIRS:-/usr/local/sbin /usr/sbin /sbin}"
shadow_candidates() {   # every copy that could run when you type the name (written with `if`: a failed test must not trip set -e)
    local d
    { type -aP "$1" 2>/dev/null || true; }
    for d in $SHADOW_DIRS; do
        if [ -e "$d/$1" ]; then echo "$d/$1"; fi
    done
}
check_shadow() {   # check_shadow NAME DEST
    [ -z "${SSW_QUIET_SHADOW:-}" ] || return 0   # the one-command installer tidies these itself
    local found
    while IFS= read -r found; do
        [ -n "$found" ] || continue
        if [ "$(readlink -f "$found")" != "$(readlink -f "$2")" ]; then
            warn "An older $1 exists at $found (v$(script_version "$found")) and can hide the new one."
            warn "Move it away:  sudo mv '$found' '$found.old' && hash -r"
        fi
    done < <(shadow_candidates "$1")
    return 0
}
check_shadow social-switch "$SS_DEST"
if [ "$WITH_CLOUDFLARE" -eq 1 ]; then check_shadow cloudflare-switch "$CF_DEST"; fi
echo
success "Core tools installed."
