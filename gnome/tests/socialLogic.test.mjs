import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {
    parseStatus, barLabel, barLevel, headline, tileState, masterRequest,
    tileAction, normalizeSite, lastErrorLine, isAuthCancelled, shortLabel,
    parseDnsStatus, dnsLabel, dnsRequest,
} from '../social-switch@diea-abdeltwab.github.io/socialLogic.js';

const mk = (over = {}) => JSON.stringify({
    schema: 2, version: '2.2.0', state: 'off', mode: 'mixed', blocked_count: 1,
    wanted_count: 1, total: 3, immutable: false,
    platforms: [
        {key: 'youtube', label: 'YouTube', blocked: true, wanted: true, status: 'blocked'},
        {key: 'twitter', label: 'X / Twitter', blocked: false, wanted: false, status: 'allowed'},
        {key: 'kick', label: 'Kick', blocked: false, wanted: false, status: 'allowed'},
    ],
    custom: [], ...over,
});

test('parses a mixed status', () => {
    const s = parseStatus(mk());
    assert.equal(s.mode, 'mixed');
    assert.equal(barLabel(s), '1/3');
    assert.equal(barLevel(s), 'mixed');
    assert.equal(headline(s), 'Mixed: 1 of 3 blocked');
});

test('garbage and old shapes', () => {
    assert.equal(parseStatus(''), null);
    assert.equal(parseStatus('{"nope":1}'), null);
    const old = parseStatus(JSON.stringify({platforms: [{key: 'a', label: 'A', blocked: true}]}));
    assert.equal(old.wantedCount, 1);          // pre-schema-2 CLIs only had `blocked`
    assert.equal(old.mode, 'off');
});

test('on / off modes', () => {
    const none = parseStatus(mk({platforms: [{key: 'a', label: 'A', blocked: false, wanted: false, status: 'allowed'}]}));
    assert.equal(barLabel(none), 'ON');
    const all = parseStatus(mk({platforms: [{key: 'a', label: 'A', blocked: true, wanted: true, status: 'blocked'}]}));
    assert.equal(barLabel(all), 'OFF');
});

test('master switch is loop-proof', () => {
    const none = parseStatus(mk({platforms: [{key: 'a', label: 'A', blocked: false, wanted: false, status: 'allowed'}]}));
    const all = parseStatus(mk({platforms: [{key: 'a', label: 'A', blocked: true, wanted: true, status: 'blocked'}]}));
    const mixed = parseStatus(mk());
    assert.deepEqual(masterRequest(none, true), ['off']);    // user flips it on  -> block all
    assert.deepEqual(masterRequest(all, false), ['on']);     // user flips it off -> allow all
    assert.deepEqual(masterRequest(mixed, true), ['off']);   // mixed -> block everything
    // echoes of a state we set ourselves must do nothing:
    assert.equal(masterRequest(none, false), null);
    assert.equal(masterRequest(all, true), null);
    assert.equal(masterRequest(mixed, false), null);
    assert.equal(masterRequest(null, true), null);
});

test('broken platform raises a warning and needs sync', () => {
    const s = parseStatus(mk({platforms: [
        {key: 'youtube', label: 'YouTube', blocked: false, wanted: true, status: 'broken'},
    ]}));
    assert.equal(s.needsSync, true);
    assert.equal(barLevel(s), 'warning');
    assert.equal(tileState(s.platforms[0]), 'warning');
    assert.deepEqual(tileAction(s.platforms[0]), ['on', 'youtube']);   // tapping releases it
});

test('external block shows as warning, tap blocks it ourselves', () => {
    const s = parseStatus(mk({platforms: [{key: 'x', label: 'X', blocked: false, wanted: false, status: 'external'}]}));
    assert.equal(tileState(s.platforms[0]), 'warning');
    assert.deepEqual(tileAction(s.platforms[0]), ['off', 'x']);
});

test('custom sites', () => {
    const s = parseStatus(mk({custom: [{domain: 'example.com', blocked: true, status: 'blocked'}, {domain: 'b.org', blocked: false, status: 'broken'}]}));
    assert.equal(s.custom.length, 2);
    assert.equal(s.needsSync, true);
});

test('normalizeSite', () => {
    assert.equal(normalizeSite('https://www.Example.com/path?q=1#x'), 'example.com');
    assert.equal(normalizeSite('user:pw@news.site.co.uk:8080/a'), 'news.site.co.uk');
    assert.equal(normalizeSite('example.com.'), 'example.com');
    for (const bad of ['', '   ', '-rf', 'localhost', 'a b.com', 'bad_host.com', '.com', null])
        assert.equal(normalizeSite(bad), null, String(bad));
});

test('error helpers', () => {
    assert.equal(lastErrorLine('\u001b[31mError:\u001b[0m something broke\n'), 'something broke');
    assert.equal(lastErrorLine(''), '');
    assert.equal(isAuthCancelled(126), true);
    assert.equal(isAuthCancelled(1), false);
    assert.equal(shortLabel({key: 'twitter', label: 'X / Twitter'}), 'X');
});

test('real CLI output', {skip: process.getuid?.() === 0 && 'test hook is ignored for root'}, () => {
    // End-to-end: feed genuine `social-switch status --json` into the parser.
    const root = new URL('../../', import.meta.url).pathname;
    const out = execFileSync('bash', ['-c',
        'W=$(mktemp -d) && mkdir -p "$W/etc" && echo "127.0.0.1 localhost" > "$W/etc/hosts" ' +
        '&& export SOCIAL_SWITCH_TEST_ROOT="$W" && core/social-switch off youtube >/dev/null && core/social-switch status --json'],
        {encoding: 'utf8', cwd: root});
    const s = parseStatus(out);
    assert.equal(s.total, 12);
    assert.equal(s.mode, 'mixed');
    assert.equal(s.platforms[0].key, 'youtube');
});

test('DNS filter status parsing and label', () => {
    const on = parseDnsStatus('{"schema":1,"state":"on","preset":"family","backend":"nm","effective":"yes","servers":["1.1.1.3"]}');
    assert.equal(on.state, 'on');
    assert.equal(dnsLabel(on), 'DNS filter: Cloudflare Family');
    const lying = parseDnsStatus('{"state":"on","preset":"malware","backend":"nm","effective":"no"}');
    assert.equal(dnsLabel(lying), 'DNS filter: Cloudflare Security (not in effect)');
    assert.equal(parseDnsStatus('nope'), null);
    assert.equal(parseDnsStatus('{"state":"maybe"}'), null);
});

test('DNS switch is loop-proof too', () => {
    const on = parseDnsStatus('{"state":"on"}');
    const off = parseDnsStatus('{"state":"off"}');
    assert.deepEqual(dnsRequest(off, true), ['on']);
    assert.deepEqual(dnsRequest(on, false), ['off']);
    assert.equal(dnsRequest(on, true), null);     // echo of our own update
    assert.equal(dnsRequest(off, false), null);
    assert.equal(dnsRequest(null, true), null);
});
