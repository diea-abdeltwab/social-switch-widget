#!/usr/bin/env bash
# Social Switch - GNOME uninstaller. Removes the extension; optionally the CLI tools.
set -euo pipefail

UUID="social-switch@diea-abdeltwab.github.io"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"

info() { printf '\033[0;36m→\033[0m  %s\n' "$*"; }
ok()   { printf '\033[0;32m✓\033[0m  %s\n' "$*"; }

read -rp "Remove the Social Switch extension? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] || { info "Nothing changed."; exit 0; }

command -v gnome-extensions >/dev/null && gnome-extensions disable "$UUID" 2>/dev/null || true
rm -rf "$DEST"
command -v dconf >/dev/null && dconf reset -f /org/gnome/shell/extensions/social-switch/ 2>/dev/null || true
ok "Extension removed"

echo
echo "The command-line tools (social-switch, cloudflare-switch) still work without the extension."
read -rp "Remove them too? This unblocks every site and turns the DNS filter off first. [y/N] " b
if [[ "$b" =~ ^[Yy]$ ]]; then
    "$HERE/../core/uninstall-core.sh"
else
    info "Kept the command-line tools."
fi
