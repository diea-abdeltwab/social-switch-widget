#!/usr/bin/env bash
# ============================================================
#  cleanup.sh - removes the leftovers of earlier installs and experiments
#
#    ./cleanup.sh            shows what it found, asks, then deletes
#    ./cleanup.sh --yes      no question
#    ./cleanup.sh --hosts-bak   also delete /etc/hosts.bak (the original hosts file
#                               social-switch saved the first time it ran)
#
#  It removes ONLY:
#    * backup folders made by earlier installers
#        ~/.local/share/social-switch-widget/   /var/backups/social-switch-widget/
#    * half-finished extension staging folders (~/.local/share/gnome-shell/.social-switch-stage.*)
#    * *.old / *.bak / *.from-* copies of the two scripts
#    * older copies of the scripts that hide the real one (~/.local/bin, /usr/local/sbin)
#    * the old v1 cloudflare-switch boot service
#  It never touches your blocked sites, your DNS settings, or the installed tools.
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info() { echo -e "${CYAN}→${RESET}  $*"; }
ok()   { echo -e "${GREEN}✓${RESET}  $*"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }

SYS="${SSW_SYS_ROOT:-}"     # empty on a real system; a temp dir in tests
ASSUME_YES=0; WITH_HOSTS_BAK=0
for a in "$@"; do
    case "$a" in
        --yes|-y) ASSUME_YES=1 ;;
        --hosts-bak) WITH_HOSTS_BAK=1 ;;
        -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 1 ;;
    esac
done
[ "$EUID" -ne 0 ] || { echo "Run as your normal user (sudo is used where needed)." >&2; exit 1; }

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALLED="$SYS/usr/local/bin"
FOUND=()        # entries: "user|path" or "root|path"
add() { [ -e "$2" ] || [ -L "$2" ] && FOUND+=("$1|$2") || true; }
looks_like_ours() { head -n 25 "$1" 2>/dev/null | grep -qE "social-switch|cloudflare-switch"; }

# 1. backups of earlier installers
add user "$DATA/social-switch-widget"
add root "$SYS/var/backups/social-switch-widget"

# 2. staging folders left by an interrupted extension install
for d in "$DATA"/gnome-shell/.social-switch-stage.*; do add user "$d"; done

# 3. renamed / backup copies of the scripts
for dir in "$HOME/.local/bin" "$SYS/usr/local/bin" "$SYS/usr/local/sbin"; do
    for f in "$dir"/social-switch.* "$dir"/cloudflare-switch.*; do
        [ -e "$f" ] || continue
        case "$f" in *.old|*.bak|*.from-*|*~) if [ "$dir" = "$HOME/.local/bin" ]; then add user "$f"; else add root "$f"; fi ;; esac
    done
done

# 4. older copies that hide the installed scripts
for name in social-switch cloudflare-switch; do
    for f in "$HOME/.local/bin/$name" "$HOME/bin/$name" "$SYS/usr/local/sbin/$name"; do
        [ -e "$f" ] || continue
        [ "$(readlink -f "$f")" = "$(readlink -f "$INSTALLED/$name" 2>/dev/null || echo)" ] && continue
        looks_like_ours "$f" || continue
        case "$f" in "$HOME"/*) add user "$f" ;; *) add root "$f" ;; esac
    done
done

# 5. v1 cloudflare-switch boot service
add root "$SYS/etc/systemd/system/cloudflare-switch-restore.service"

# 6. optional
[ "$WITH_HOSTS_BAK" -eq 0 ] || add root "$SYS/etc/hosts.bak"

if [ "${#FOUND[@]}" -eq 0 ]; then
    ok "Nothing to clean - already tidy."
    exit 0
fi

info "Found ${#FOUND[@]} leftover(s):"
for e in "${FOUND[@]}"; do echo "     ${e#*|}"; done
if [ "$ASSUME_YES" -eq 0 ]; then
    read -rp "Delete them? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] || { info "Nothing deleted."; exit 0; }
fi

need_sudo=0; HAD_UNIT=0
for e in "${FOUND[@]}"; do [ "${e%%|*}" = root ] && need_sudo=1; done
[ "$need_sudo" -eq 0 ] || sudo -v

for e in "${FOUND[@]}"; do
    kind="${e%%|*}"; path="${e#*|}"
    if [ "$kind" = root ]; then
        case "$path" in *cloudflare-switch-restore.service)
            HAD_UNIT=1
            if command -v systemctl >/dev/null; then sudo systemctl disable --now cloudflare-switch-restore.service >/dev/null 2>&1 || true; fi ;;
        esac
        if [ "$path" = "$SYS/etc/hosts.bak" ]; then sudo chattr -i "$path" 2>/dev/null || true; fi
        sudo rm -rf "$path"
    else
        rm -rf "$path"
    fi
done
if [ "$HAD_UNIT" -eq 1 ] && command -v systemctl >/dev/null; then
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
fi
hash -r 2>/dev/null || true
ok "Cleaned up ${#FOUND[@]} item(s)."
echo "    Run  hash -r  in your shell so it forgets the removed commands."
