#!/usr/bin/env bash
# Removes social-switch-widget: delegates to the edition's uninstaller.
# Same detection order as install.sh (GNOME first), or force one:  ./uninstall.sh gnome|omarchy|core
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

edition="${1:-}"
if [ -z "$edition" ]; then
    desktop="${XDG_CURRENT_DESKTOP:-}"
    if [[ "${desktop,,}" == *gnome* ]] || command -v gnome-shell >/dev/null 2>&1; then edition=gnome
    elif command -v omarchy >/dev/null 2>&1 || [ -d "$HOME/.config/omarchy" ]; then edition=omarchy
    else edition=core; fi
fi

case "$edition" in
    gnome)   exec "$HERE/gnome/uninstall.sh" ;;
    omarchy) exec "$HERE/omarchy-quatto/uninstall.sh" ;;
    core)    exec "$HERE/core/uninstall-core.sh" ;;
    *) echo "usage: ./uninstall.sh [gnome|omarchy|core]" >&2; exit 1 ;;
esac
