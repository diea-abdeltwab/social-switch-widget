#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Offline tests for social-switch against a throw-away fake /etc.
# Must run as a NON-root user:  runuser -u nobody -- bash tests/test_social_switch.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SS="$HERE/social-switch"
[ "$EUID" -ne 0 ] || { echo "run as a normal user"; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SOCIAL_SWITCH_TEST_ROOT="$W"
mkdir -p "$W/etc"; printf '127.0.0.1 localhost\n10.0.0.5 myserver\n' > "$W/etc/hosts"
pass=0; fail=0
check(){ if eval "$2"; then pass=$((pass+1)); echo "  ok   - $1"; else fail=$((fail+1)); echo "  FAIL - $1"; fi; }
ss(){ "$SS" "$@"; }
json(){ ss status --json | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

echo "== basics =="
check "starts as on/none blocked"      '[ "$(json "d[\"mode\"]")" = on ] && [ "$(json "d[\"state\"]")" = on ]'
ss off youtube kick >/dev/null
check "blocks two platforms"           '[ "$(json "d[\"blocked_count\"]")" = 2 ]'
check "mode mixed, legacy state off"   '[ "$(json "d[\"mode\"]")" = mixed ] && [ "$(json "d[\"state\"]")" = off ]'
check "hosts has youtube entries"      'grep -q "^0.0.0.0 youtube.com" "$W/etc/hosts"'
check "foreign hosts lines preserved"  'grep -q "10.0.0.5 myserver" "$W/etc/hosts"'
ss on youtube >/dev/null
check "unblock one platform"           '[ "$(json "d[\"blocked_count\"]")" = 1 ]'
ss off >/dev/null
check "off = block all 12"             '[ "$(json "d[\"mode\"]")" = off ] && [ "$(json "d[\"blocked_count\"]")" = 12 ]'
ss on >/dev/null
check "on = allow all"                 '[ "$(json "d[\"mode\"]")" = on ] && [ "$(json "d[\"blocked_count\"]")" = 0 ]'
check "foreign lines still there"      'grep -q "10.0.0.5 myserver" "$W/etc/hosts"'
ss off --except twitter >/dev/null
check "off --except twitter"           '[ "$(json "d[\"blocked_count\"]")" = 11 ] && ! grep -q "^0.0.0.0 x.com" "$W/etc/hosts"'
ss on >/dev/null

echo "== custom sites =="
ss off https://www.example.com/some/path >/dev/null
check "URL normalised to example.com"  '[ "$(json "d[\"custom\"][0][\"domain\"]")" = example.com ]'
check "www. variant also blocked"      'grep -q "^0.0.0.0 www.example.com" "$W/etc/hosts"'
ss on example.com >/dev/null
check "custom site unblocked"          '[ "$(json "len(d[\"custom\"])")" = 0 ]'
check "rejects option-looking input"   '! ss off -- -rf >/dev/null 2>&1'
check "rejects garbage host"           '! ss off "bad host!" >/dev/null 2>&1'

echo "== upgrade safety (platforms from older builds) =="
printf 'facebook\nmessenger\ntumblr\n' > "$W/etc/social-switch/blocked"; rm -f "$W/etc/social-switch/custom"
ss sync >/dev/null
check "messenger kept blocked as custom" 'grep -q "^0.0.0.0 messenger.com" "$W/etc/hosts"'
check "tumblr kept blocked as custom"    'grep -q "^0.0.0.0 tumblr.com" "$W/etc/hosts"'
check "state file rewritten cleanly"     '[ "$(cat $W/etc/social-switch/blocked)" = facebook ]'
ss on messenger >/dev/null
check "old name still works to unblock"  '! grep -q "^0.0.0.0 messenger.com" "$W/etc/hosts" && grep -q "^0.0.0.0 tumblr.com" "$W/etc/hosts"'
ss on >/dev/null; ss on tumblr.com >/dev/null

echo "== self-healing =="
ss off reddit >/dev/null
printf '127.0.0.1 localhost\n' > "$W/etc/hosts"      # another tool rewrote the file
check "status reports broken"          '[ "$(json "[p[\"status\"] for p in d[\"platforms\"] if p[\"key\"]==\"reddit\"][0]")" = broken ]'
check "wanted_count survives"          '[ "$(json "d[\"wanted_count\"]")" = 1 ]'
ss sync >/dev/null
check "sync repairs it"                'grep -q "^0.0.0.0 reddit.com" "$W/etc/hosts"'
ss on >/dev/null

echo "== config =="
printf 'LOCK_HOSTS=no\n' > "$W/etc/social-switch/config"
check "config accepted"                'ss off tiktok >/dev/null'
check "json schema marker"             '[ "$(json "d[\"schema\"]")" = 2 ]'
check "markers balanced after churn"   '[ "$(grep -c "BEGIN social-switch" "$W/etc/hosts")" = "$(grep -c "END social-switch" "$W/etc/hosts")" ]'
check "version"                        'ss version | grep -q "^social-switch 2\."'

echo; echo "passed: $pass  failed: $fail"; [ "$fail" -eq 0 ]
