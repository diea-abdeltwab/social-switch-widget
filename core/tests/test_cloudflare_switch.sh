#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are read through eval inside check()
# Offline tests for cloudflare-switch using fake nmcli/systemctl/resolvectl/getent.
# Must run as a NON-root user (the test hook is ignored for root on purpose).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/cloudflare-switch"
[ "$EUID" -ne 0 ] || { echo "run as a normal user (e.g. runuser -u nobody -- $0)"; exit 2; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export CLOUDFLARE_SWITCH_TEST_ROOT="$W/root" MOCK="$W/mock"
mkdir -p "$W/root/etc" "$MOCK/bin" "$MOCK/profiles"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   - $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL - $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ---- fake NetworkManager: profiles live in $MOCK/profiles/<uuid>/<prop> ----
mkprofile(){ mkdir -p "$MOCK/profiles/$1"; echo "$2" > "$MOCK/profiles/$1/type"; echo "$3" > "$MOCK/profiles/$1/ipv4.dns"; echo "${4:-no}" > "$MOCK/profiles/$1/ipv4.ignore-auto-dns"; : > "$MOCK/profiles/$1/ipv6.dns"; echo no > "$MOCK/profiles/$1/ipv6.ignore-auto-dns"; }
cat > "$MOCK/bin/nmcli" <<'NM'
#!/usr/bin/env bash
P="$MOCK/profiles"
args="$*"
case "$args" in
  "-t -f RUNNING general") echo running ;;
  "-t -f UUID,TYPE connection show") for d in "$P"/*/; do u=$(basename "$d"); echo "$u:$(cat "$d/type")"; done ;;
  "-t -f UUID,DEVICE connection show --active") echo "aaaa-1111:eth0" ;;
  "-t -f DEVICE,TYPE,STATE device") echo "eth0:ethernet:connected" ;;
  "device reapply"*) echo reapply >> "$MOCK/log" ;;
  "-g IP4.DNS,IP6.DNS device show eth0")
      if [ "$(cat "$P/aaaa-1111/ipv4.ignore-auto-dns")" = yes ]; then echo "$(tr ',' ' ' < "$P/aaaa-1111/ipv4.dns" | sed 's/ /|/g')"; else echo "192.168.1.1"; fi ;;
  "-g connection.id connection show "*) echo "profile-$5" ;;
  "-g "*" connection show "*) prop="$2"; u="$5"; [ -f "$P/$u/$prop" ] && sed 's/:/\\:/g' "$P/$u/$prop" || exit 10 ;;
  "connection modify "*)
      u="$3"; shift 3
      [ -f "$MOCK/reject_v6" ] && [[ "$*" == ipv6.* ]] && exit 4
      while [ "$#" -gt 0 ]; do printf '%s\n' "$2" | tr ' ' ',' > "$P/$u/$1"; shift 2; done ;;
  "connection up"*) echo up >> "$MOCK/log" ;;
  *) echo "mock nmcli: unhandled: $args" >&2; exit 2 ;;
esac
NM
cat > "$MOCK/bin/getent" <<'G'
#!/usr/bin/env bash
[ -f "$MOCK/dns_broken" ] && exit 2; echo "93.184.216.34 $2"
G
cat > "$MOCK/bin/systemctl" <<'S'
#!/usr/bin/env bash
echo "systemctl $*" >> "$MOCK/log"; case "$1" in is-active) [ -f "$MOCK/resolved_active" ] && exit 0 || exit 3 ;; esac; exit 0
S
cat > "$MOCK/bin/resolvectl" <<'R'
#!/usr/bin/env bash
case "$1" in
  dns) if [ -f "$CLOUDFLARE_SWITCH_TEST_ROOT/etc/systemd/resolved.conf.d/90-cloudflare-switch.conf" ]; then echo "Global: 1.1.1.3 1.0.0.3 2606:4700:4700::1113 2606:4700:4700::1003"; else echo "Global:"; echo "Link 2 (eth0): 192.168.1.1"; fi ;;
  *) : ;;
esac
R
chmod +x "$MOCK"/bin/*
export PATH="$MOCK/bin:$PATH"
cs(){ "$SCRIPT" "$@"; }

echo "== NetworkManager backend =="
mkprofile aaaa-1111 802-3-ethernet "" no
mkprofile bbbb-2222 802-11-wireless "9.9.9.9" no
mkprofile cccc-3333 vpn "" no
check "detects nm"                 'cs status --short | grep -q "^off"'
cs on family >/dev/null 2>&1
check "state saved as on"          '[ "$(cat $W/root/etc/cloudflare-switch/state)" = on ]'
check "ethernet profile set"       'grep -q "1.1.1.3" $MOCK/profiles/aaaa-1111/ipv4.dns'
check "ignore-auto-dns yes"        '[ "$(cat $MOCK/profiles/aaaa-1111/ipv4.ignore-auto-dns)" = yes ]'
check "wifi profile set"           'grep -q "1.0.0.3" $MOCK/profiles/bbbb-2222/ipv4.dns'
check "vpn profile untouched"      '[ -z "$(cat $MOCK/profiles/cccc-3333/ipv4.dns)" ]'
check "originals saved (9.9.9.9)"  'grep -q "ipv4.dns=9.9.9.9" $W/root/var/lib/cloudflare-switch/nm/bbbb-2222'
check "effective yes"              'cs status --json | grep -q "\"effective\":\"yes\""'
check "json backend nm"            'cs status --json | grep -q "\"backend\":\"nm\""'
cs on malware >/dev/null 2>&1
check "preset switch keeps originals" 'grep -q "ipv4.dns=9.9.9.9" $W/root/var/lib/cloudflare-switch/nm/bbbb-2222 && grep -q "1.1.1.2" $MOCK/profiles/bbbb-2222/ipv4.dns'
cs off >/dev/null 2>&1
check "wifi DNS restored"          '[ "$(cat $MOCK/profiles/bbbb-2222/ipv4.dns)" = "9.9.9.9" ] && [ "$(cat $MOCK/profiles/bbbb-2222/ipv4.ignore-auto-dns)" = no ]'
check "ethernet DNS restored"      '[ -z "$(cat $MOCK/profiles/aaaa-1111/ipv4.dns)" ]'
check "saved copies removed"       '[ -z "$(ls $W/root/var/lib/cloudflare-switch/nm 2>/dev/null)" ]'
check "status off"                 'cs status --short | grep -q "^off"'

echo "== profile that rejects IPv6 DNS =="
touch "$MOCK/reject_v6"; cs on family >/dev/null 2>&1; rc=$?
check "still succeeds with v4 only" '[ $rc -eq 0 ] && grep -q 1.1.1.3 $MOCK/profiles/aaaa-1111/ipv4.dns'
rm -f "$MOCK/reject_v6"; cs off >/dev/null 2>&1

echo "== rollback when DNS breaks =="
cat > "$MOCK/bin/nmcli.real" < "$MOCK/bin/nmcli"
# simulate: after the change DNS dies
cp "$MOCK/bin/nmcli" "$MOCK/bin/nmcli.keep"
sed -i 's|"connection modify "\*)|"connection modify "*) touch "$MOCK/dns_broken_after"; |' "$MOCK/bin/nmcli"
cat > "$MOCK/bin/getent" <<'G'
#!/usr/bin/env bash
if [ -f "$MOCK/dns_broken_after" ] && [ "$(cat "$MOCK/profiles/aaaa-1111/ipv4.ignore-auto-dns")" = yes ]; then exit 2; fi
echo "1.2.3.4 $2"
G
cs on family >/dev/null 2>&1; rc=$?
check "on fails when DNS dies"     '[ $rc -ne 0 ]'
check "rolled back to original"    '[ -z "$(cat $MOCK/profiles/aaaa-1111/ipv4.dns)" ] && [ "$(cat $MOCK/profiles/aaaa-1111/ipv4.ignore-auto-dns)" = no ]'
check "state not set to on"        '[ ! -f $W/root/etc/cloudflare-switch/state ] || [ "$(cat $W/root/etc/cloudflare-switch/state)" != on ]'
rm -f "$MOCK/dns_broken_after"; cp "$MOCK/bin/nmcli.keep" "$MOCK/bin/nmcli"

echo "== systemd-resolved backend =="
rm -f "$MOCK/bin/nmcli"; touch "$MOCK/resolved_active"
cat > "$MOCK/bin/getent" <<'G'
#!/usr/bin/env bash
echo "1.2.3.4 $2"
G
cs on family >/dev/null 2>&1
D="$W/root/etc/systemd/resolved.conf.d/90-cloudflare-switch.conf"
check "drop-in written"            'grep -q "^DNS=1.1.1.3 1.0.0.3" "$D" && grep -q "^Domains=~\." "$D"'
check "resolved restarted"         'grep -q "restart systemd-resolved" $MOCK/log'
check "status effective yes"       'cs status --json | grep -q "\"backend\":\"resolved\"" && cs status --json | grep -q "\"effective\":\"yes\""'
cs off >/dev/null 2>&1
check "drop-in removed"            '[ ! -e "$D" ]'

echo "== v1 leftovers =="
mkdir -p "$W/root/etc/systemd/system"; echo x > "$W/root/etc/systemd/system/cloudflare-switch-restore.service"
cs on family >/dev/null 2>&1
check "old v1 boot unit removed"   '[ ! -e "$W/root/etc/systemd/system/cloudflare-switch-restore.service" ]'
cs off >/dev/null 2>&1

echo "== resolv.conf backend =="
rm -f "$MOCK/resolved_active" "$MOCK/bin/resolvectl"
printf 'nameserver 192.168.1.1\n' > "$W/root/etc/resolv.conf"
cs on family >/dev/null 2>&1
check "nameservers written"        'grep -q "^nameserver 1.1.1.3" "$W/root/etc/resolv.conf"'
cs off >/dev/null 2>&1
check "original resolv.conf back"  '[ "$(cat $W/root/etc/resolv.conf)" = "nameserver 192.168.1.1" ]'
ln -sf /run/foo "$W/root/etc/resolv.conf.link"; mv -f "$W/root/etc/resolv.conf.link" "$W/root/etc/resolv.conf"
cs on family >/dev/null 2>&1; rc=$?
check "refuses symlinked resolv.conf" '[ $rc -ne 0 ]'

echo "== misc =="
check "bad preset rejected"        '! cs on bogus >/dev/null 2>&1'
check "version"                    'cs version | grep -q "^cloudflare-switch 2"'

echo; echo "passed: $pass  failed: $fail"; [ "$fail" -eq 0 ]
