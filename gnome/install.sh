#!/usr/bin/env bash
# Social Switch - GNOME Shell installer (Fedora, Ubuntu, Debian, Arch, openSUSE ... any GNOME 45+).
#
#   1. installs the shared CLI tools + polkit policy  (needs sudo; see ../core)
#   2. copies the extension into your user directory  (no root)
#   3. compiles its settings schema and enables it
#
# Safe to re-run. Options:  --yes (no questions)   --no-cloudflare   --skip-core
set -euo pipefail

UUID="social-switch@diea-abdeltwab.github.io"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$HERE/../core"
SRC="$HERE/$UUID"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"

info() { printf '\033[0;36m→\033[0m  %s\n' "$*"; }
ok()   { printf '\033[0;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m  %s\n' "$*"; }
die()  { printf '\033[0;31m✗\033[0m  %s\n' "$*" >&2; exit 1; }

CORE_ARGS=(); SKIP_CORE=0
for a in "$@"; do
    case "$a" in
        --yes|-y|--no-cloudflare) CORE_ARGS+=("$a") ;;
        --skip-core) SKIP_CORE=1 ;;
        -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown option: $a" ;;
    esac
done

[ -d "$SRC" ]  || die "Extension folder not found next to install.sh: $SRC"
[ -f "$CORE/social-switch" ] || die "../core/social-switch not found - run this from a full clone of the repository."
[ "$EUID" -ne 0 ] || die "Run this as your normal user (it uses sudo only where needed)."
command -v glib-compile-schemas >/dev/null \
    || die "glib-compile-schemas not found. Fedora: sudo dnf install glib2-devel | Debian/Ubuntu: sudo apt install libglib2.0-bin | Arch: sudo pacman -S glib2"
command -v gnome-extensions >/dev/null || warn "gnome-extensions not found - you will need to enable the extension by hand"

if command -v gnome-shell >/dev/null; then
    ver="$(gnome-shell --version | awk '{print $3}')"
    ok "GNOME Shell $ver detected"
    [ "${ver%%.*}" -ge 45 ] 2>/dev/null || die "GNOME Shell 45 or newer is required (found $ver)."
fi

# ── 1. CLI tools ─────────────────────────────────────────────────────────────
if [ "$SKIP_CORE" -eq 0 ]; then
    info "Installing the command-line tools (sudo will ask for your password)..."
    "$CORE/install-core.sh" "${CORE_ARGS[@]}"
else
    info "Skipping the CLI tools (--skip-core)"
fi

# ── 2. Extension files ──────────────────────────────────────────────────────────
# GNOME Shell watches the extensions folder and tries to enable a new extension
# the moment its files appear. So build it completely (schema compiled) in a
# staging folder OUTSIDE that watched folder, then move it into place in one step.
info "Installing the extension to $DEST"
STAGE="$(dirname "$(dirname "$DEST")")/.social-switch-stage.$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -r "$SRC"/. "$STAGE"/
glib-compile-schemas "$STAGE/schemas"
[ -f "$STAGE/schemas/gschemas.compiled" ] || { rm -rf "$STAGE"; die "schema compilation produced no gschemas.compiled"; }
if command -v gsettings >/dev/null; then
    gsettings --schemadir "$STAGE/schemas" list-keys org.gnome.shell.extensions.social-switch >/dev/null 2>&1 \
        || { rm -rf "$STAGE"; die "the compiled schema does not contain org.gnome.shell.extensions.social-switch"; }
fi
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mv "$STAGE" "$DEST"
ok "Extension installed, settings schema compiled and verified"

# ── 3. Enable ─────────────────────────────────────────────────────────────────────
if command -v gnome-extensions >/dev/null; then
    if gnome-extensions enable "$UUID" 2>/dev/null; then
        ok "Enabled $UUID"
    else
        warn "GNOME does not know the new extension yet (normal on first install)."
    fi
fi

echo
ok "Done."
echo
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    warn "You are on Wayland: log out and back in once so GNOME Shell discovers the extension,"
    echo "    then run:  gnome-extensions enable $UUID"
else
    echo "    Press Alt+F2, type  r  and Enter to restart GNOME Shell, then:"
    echo "    gnome-extensions enable $UUID"
fi
echo
echo "    Logs if the icon does not appear:  journalctl -f -o cat /usr/bin/gnome-shell"
echo "    Uninstall:                         ./uninstall.sh"
