// Pure logic for the Social Switch extension - no GNOME imports, so it can be
// unit-tested with plain Node (see ../tests/socialLogic.test.mjs).
//
// Vocabulary (same as the CLI and the Omarchy widget):
//   ON  = social media is allowed        OFF = blocked

export const TILE_COLUMNS = 3;

const SHORT_LABELS = {
    twitter: 'X',
};

export function shortLabel(platform) {
    return SHORT_LABELS[platform.key] ?? platform.label;
}

/**
 * Parse the output of `social-switch status --json` (schema 1 or 2).
 * Returns null when the text is not usable.
 */
export function parseStatus(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (_e) {
        return null;
    }
    if (!raw || !Array.isArray(raw.platforms))
        return null;

    const platforms = raw.platforms.map(p => {
        const status = typeof p.status === 'string' ? p.status : (p.blocked ? 'blocked' : 'allowed');
        // `wanted` = what the user asked for; older CLIs only knew `blocked`.
        const wanted = typeof p.wanted === 'boolean' ? p.wanted : status === 'blocked';
        return {key: String(p.key), label: String(p.label ?? p.key), status, wanted};
    });

    const custom = Array.isArray(raw.custom)
        ? raw.custom.map(c => ({
            domain: String(c.domain),
            status: typeof c.status === 'string' ? c.status : (c.blocked ? 'blocked' : 'broken'),
        }))
        : [];

    const total = platforms.length;
    const wantedCount = platforms.filter(p => p.wanted).length;
    const blockedCount = platforms.filter(p => p.status === 'blocked').length;
    const needsSync =
        platforms.some(p => p.wanted && p.status !== 'blocked') ||
        custom.some(c => c.status !== 'blocked');
    const external = platforms.some(p => p.status === 'external');

    let mode = 'mixed';
    if (wantedCount === 0)
        mode = 'on';
    else if (wantedCount === total)
        mode = 'off';

    return {
        version: raw.version ?? 'unknown',
        platforms, custom, total, wantedCount, blockedCount,
        mode, needsSync, external,
        immutable: Boolean(raw.immutable),
    };
}

/** Text for the panel label. */
export function barLabel(status) {
    if (!status)
        return '';
    if (status.mode === 'on')
        return 'ON';
    if (status.mode === 'off')
        return 'OFF';
    return `${status.wantedCount}/${status.total}`;
}

/** CSS state class suffix for the indicator. */
export function barLevel(status) {
    if (!status)
        return 'unknown';
    if (status.needsSync)
        return 'warning';
    return status.mode === 'on' ? 'allowed' : status.mode === 'off' ? 'blocked' : 'mixed';
}

/** Headline inside the popup. */
export function headline(status) {
    if (!status)
        return 'Social Switch';
    if (status.mode === 'on')
        return 'Social media is ON (allowed)';
    if (status.mode === 'off')
        return 'Social media is OFF (blocked)';
    return `Mixed: ${status.wantedCount} of ${status.total} blocked`;
}

/** Style suffix for one platform tile. */
export function tileState(platform) {
    if (platform.wanted && platform.status !== 'blocked')
        return 'warning';          // saved as blocked but missing from /etc/hosts
    if (!platform.wanted && platform.status === 'external')
        return 'warning';          // another hosts entry blocks it
    return platform.status === 'blocked' ? 'blocked' : 'allowed';
}

/**
 * What should the master switch do when it reports `wantBlocked`?
 *   switch ON  = block everything       switch OFF = allow everything
 * Returns CLI arguments, or null when the request already matches reality.
 * The null case is what makes the switch loop-proof: if GNOME re-announces a
 * state we set ourselves, it matches the status and nothing is run.
 */
export function masterRequest(status, wantBlocked) {
    if (!status)
        return null;
    const isBlocked = status.mode === 'off';
    if (Boolean(wantBlocked) === isBlocked)
        return null;
    return wantBlocked ? ['off'] : ['on'];
}

/** CLI arguments for tapping a platform tile. */
export function tileAction(platform) {
    return [platform.wanted ? 'on' : 'off', platform.key];
}

// Strict enough to give instant feedback; the CLI validates again.
const HOST_RE = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

/** Reduce what a user typed (URL, www., path ...) to a bare host, or null. */
export function normalizeSite(input) {
    let s = String(input ?? '').trim().toLowerCase();
    if (!s || /\s/.test(s) || s.startsWith('-'))
        return null;
    s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, '');   // scheme
    s = s.replace(/^[^@/]*@/, '');                   // user:pass@
    s = s.split(/[/?#]/)[0];                         // path, query, fragment
    s = s.replace(/:\d+$/, '');                      // port
    s = s.replace(/\.$/, '').replace(/^www\./, '');
    return HOST_RE.test(s) ? s : null;
}

/** Last meaningful line of stderr, without colour codes. */
export function lastErrorLine(stderr) {
    const clean = String(stderr ?? '').replace(/\u001b\[[0-9;]*m/g, '');
    const lines = clean.split('\n').map(l => l.trim()).filter(Boolean);
    const err = [...lines].reverse().find(l => /^error:/i.test(l));
    return (err ?? lines[lines.length - 1] ?? '').replace(/^error:\s*/i, '');
}

/** pkexec exit codes: 126 = not authorised / dismissed, 127 = could not authenticate. */
export function isAuthCancelled(exitCode) {
    return exitCode === 126 || exitCode === 127;
}

// ── DNS filter (cloudflare-switch) ─────────────────────────────────────────────
// Optional row in the popup; hidden unless enabled in Preferences.

const PRESET_NAMES = {
    family: 'Cloudflare Family',
    malware: 'Cloudflare Security',
    standard: 'Cloudflare',
};

/** Parse `cloudflare-switch status --json`; null when unusable. */
export function parseDnsStatus(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (_e) {
        return null;
    }
    if (!raw || (raw.state !== 'on' && raw.state !== 'off'))
        return null;
    return {
        state: raw.state,
        preset: typeof raw.preset === 'string' ? raw.preset : 'family',
        backend: typeof raw.backend === 'string' ? raw.backend : 'unknown',
        effective: typeof raw.effective === 'string' ? raw.effective : 'unknown',
    };
}

/** Text for the DNS switch row. */
export function dnsLabel(dns) {
    const name = PRESET_NAMES[dns?.preset] ?? 'Cloudflare';
    if (dns && dns.state === 'on' && dns.effective === 'no')
        return `DNS filter: ${name} (not in effect)`;
    return `DNS filter: ${name}`;
}

/**
 * Same loop-proof rule as masterRequest: returns CLI args, or null when the
 * request already matches the real state (an echo of our own update).
 */
export function dnsRequest(dns, wantOn) {
    if (!dns)
        return null;
    if (Boolean(wantOn) === (dns.state === 'on'))
        return null;
    return [wantOn ? 'on' : 'off'];
}
