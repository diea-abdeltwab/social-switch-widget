#!/usr/bin/env bash
# uninstall-core.sh - removes the shared CLI tools + polkit policy.
# Always unblocks everything and turns the DNS filter off FIRST, so removing the
# tools can never leave /etc/hosts locked or your DNS overridden.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info()    { echo -e "${CYAN}→${RESET}  $*"; }
success() { echo -e "${GREEN}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }

PREFIX="${PREFIX:-/usr/local}"
SS="$PREFIX/bin/social-switch"
CF="$PREFIX/bin/cloudflare-switch"
POLICY="/usr/share/polkit-1/actions/com.diea.socialswitch.policy"
CF_POLICY="/usr/share/polkit-1/actions/com.diea.cloudflareswitch.policy"

if [ -x "$SS" ]; then
    info "Unblocking everything and unlocking /etc/hosts..."
    sudo "$SS" on >/dev/null 2>&1 || warn "could not auto-unblock; check /etc/hosts (backup: /etc/hosts.bak)"
fi
if [ -x "$CF" ] && [ "$("$CF" status --short 2>/dev/null | cut -c1-2)" = "on" ]; then
    info "Turning the Cloudflare DNS filter off..."
    sudo "$CF" off >/dev/null 2>&1 || warn "could not restore DNS automatically; run: sudo cloudflare-switch off"
fi

sudo rm -f "$SS" "$CF" "$POLICY" "$CF_POLICY"
read -rp "  Also delete saved state (/etc/social-switch, /etc/cloudflare-switch, /var/lib/cloudflare-switch)? [y/N] " a
if [[ "$a" =~ ^[Yy]$ ]]; then
    sudo rm -rf /etc/social-switch /etc/cloudflare-switch /var/lib/cloudflare-switch
    success "State removed"
fi
success "Core tools removed."
