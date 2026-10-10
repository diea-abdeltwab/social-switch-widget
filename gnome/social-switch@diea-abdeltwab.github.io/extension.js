// Social Switch - GNOME Shell extension (GNOME 45+)
//
// A top-bar lock icon with a popup: one master switch + one tile per platform.
// All real work is done by the `social-switch` command-line tool. This file only
//   * reads   `social-switch status --json`            (no privileges)
//   * writes  `pkexec social-switch <on|off|sync> ...` (polkit asks for a password)
//
// Vocabulary matches the CLI:  ON = social media allowed, OFF = blocked.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {
    TILE_COLUMNS, parseStatus, barLabel, barLevel, headline, shortLabel,
    tileState, masterRequest, tileAction, normalizeSite, lastErrorLine, isAuthCancelled,
    parseDnsStatus, dnsLabel, dnsRequest,
} from './socialLogic.js';

const REFRESH_SECONDS = 60;
const DEBOUNCE_MS = 400;
const BUSY_FAILSAFE_SECONDS = 120;
const COOLDOWN_US = 1500 * 1000;       // minimum gap between two privileged actions
const BUILD = '1.1.0';

// The CLI runs as root through pkexec, so it must live in a root-owned place:
// a script in $HOME could be swapped by anything running as you.
const CLI_DIRS = ['/usr/local/bin', '/usr/bin'];

const POSITIONS = {left: [0, 'left'], center: [0, 'center'], right: [0, 'right']};

const LEVEL_CLASSES = ['unknown', 'allowed', 'mixed', 'blocked', 'warning']
    .map(l => `social-switch-level-${l}`);

function findCli(name = 'social-switch') {
    return CLI_DIRS.map(d => `${d}/${name}`)
        .find(p => GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE)) ?? null;
}

/** Run a command without blocking the shell. Never rejects. */
function run(argv, cancellable) {
    return new Promise(resolve => {
        let proc;
        try {
            proc = Gio.Subprocess.new(argv,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (e) {
            resolve({exit: -1, stdout: '', stderr: String(e.message ?? e)});
            return;
        }
        proc.communicate_utf8_async(null, cancellable, (p, res) => {
            try {
                const [, stdout, stderr] = p.communicate_utf8_finish(res);
                resolve({exit: p.get_exit_status(), stdout: stdout ?? '', stderr: stderr ?? ''});
            } catch (e) {
                resolve({exit: -1, stdout: '', stderr: String(e.message ?? e)});
            }
        });
    });
}

const SocialSwitchIndicator = GObject.registerClass(
class SocialSwitchIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'Social Switch', false);
        this._ext = extension;
        this._settings = extension.getSettings();
        this._cancellable = new Gio.Cancellable();
        this._status = null;
        this._dns = null;
        this._note = '';
        this._busy = false;
        this._cooldownUntil = 0;
        this._fetching = false;
        this._pending = false;
        this._destroyed = false;
        this._cliMissing = false;
        this._timers = new Set();
        this._signals = [];

        // ── panel button ──
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._icon = new St.Icon({
            icon_name: 'changes-allow-symbolic',
            style_class: 'system-status-icon social-switch-icon',
        });
        this._label = new St.Label({
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'social-switch-label',
        });
        box.add_child(this._icon);
        box.add_child(this._label);
        this.add_child(box);

        this._buildMenu();

        this._connect(this._settings, 'changed::show-label', () => this._render());
        this._connect(this._settings, 'changed::show-dns-row', () => this.refresh());
        this._connect(this.menu, 'open-state-changed', (_m, open) => {
            if (open)
                this.refresh();
            else
                this._entry.set_text('');
        });

        this._render();
        this.refresh();
    }

    // ── menu ─────────────────────────────────────────────────────────────────
    _buildMenu() {
        this._headline = new PopupMenu.PopupMenuItem('Social Switch', {reactive: false, can_focus: false});
        this._headline.label.add_style_class_name('social-switch-headline');
        this.menu.addMenuItem(this._headline);

        this._noteItem = new PopupMenu.PopupMenuItem('', {reactive: false, can_focus: false});
        this._noteItem.label.add_style_class_name('social-switch-note');
        this._noteItem.visible = false;
        this.menu.addMenuItem(this._noteItem);

        this._master = new PopupMenu.PopupSwitchMenuItem('Block everything', false);
        this._updatingSwitch = false;
        this._master.connect('toggled', (_item, state) => this._onMasterToggled(state));
        this.menu.addMenuItem(this._master);

        const tileItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        this._tiles = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'social-switch-tiles'});
        tileItem.add_child(this._tiles);
        this.menu.addMenuItem(tileItem);

        this._customMenu = new PopupMenu.PopupSubMenuMenuItem('Custom sites');
        this._customMenu.visible = false;
        this.menu.addMenuItem(this._customMenu);

        const entryItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        this._entry = new St.Entry({
            hint_text: 'Block a site, e.g. example.com',
            can_focus: true,
            x_expand: true,
            style_class: 'social-switch-entry',
        });
        this._entry.clutter_text.connect('activate', () => this._addSite());
        entryItem.add_child(this._entry);
        this.menu.addMenuItem(entryItem);

        this._dnsSeparator = new PopupMenu.PopupSeparatorMenuItem();
        this.menu.addMenuItem(this._dnsSeparator);
        this._updatingDns = false;
        this._dnsItem = new PopupMenu.PopupSwitchMenuItem('DNS filter', false);
        this._dnsItem.connect('toggled', (_item, state) => this._onDnsToggled(state));
        this.menu.addMenuItem(this._dnsItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._syncItem = new PopupMenu.PopupMenuItem('Re-apply saved blocks');
        this._syncItem.connect('activate', () => this._privileged(['sync']));
        this._syncItem.visible = false;
        this.menu.addMenuItem(this._syncItem);

        const refresh = new PopupMenu.PopupMenuItem('Refresh');
        refresh.connect('activate', () => this.refresh());
        this.menu.addMenuItem(refresh);

        const prefs = new PopupMenu.PopupMenuItem('Settings');
        prefs.connect('activate', () => this._ext.openPreferences());
        this.menu.addMenuItem(prefs);
    }

    // ── rendering ──────────────────────────────────────────────────────────
    _render() {
        const st = this._status;
        const level = barLevel(st);

        LEVEL_CLASSES.forEach(c => this._icon.remove_style_class_name(c));
        this._icon.add_style_class_name(`social-switch-level-${level}`);
        this._icon.icon_name = level === 'warning' ? 'dialog-warning-symbolic'
            : level === 'allowed' || level === 'unknown' ? 'changes-allow-symbolic'
                : 'changes-prevent-symbolic';

        const showLabel = this._settings.get_boolean('show-label') && st !== null;
        this._label.text = showLabel ? barLabel(st) : '';
        this._label.visible = showLabel;

        this._headline.label.text = this._cliMissing ? 'social-switch is not installed' : headline(st);
        this._noteItem.label.text = this._note;
        this._noteItem.visible = this._note !== '';

        // Programmatic change: must never be mistaken for a click (see _onMasterToggled).
        this._updatingSwitch = true;
        try {
            this._master.setToggleState(st !== null && st.mode === 'off');
        } finally {
            this._updatingSwitch = false;
        }
        this._master.label.text = st && st.mode === 'mixed'
            ? `Block everything (${st.wantedCount}/${st.total} now)` : 'Block everything';
        this._master.setSensitive(st !== null && !this._busy);

        const showDns = this._settings.get_boolean('show-dns-row') && this._dns !== null;
        this._dnsSeparator.visible = showDns;
        this._dnsItem.visible = showDns;
        if (showDns) {
            this._dnsItem.label.text = dnsLabel(this._dns);
            this._updatingDns = true;       // programmatic change - see _onDnsToggled
            try {
                this._dnsItem.setToggleState(this._dns.state === 'on');
            } finally {
                this._updatingDns = false;
            }
            this._dnsItem.setSensitive(!this._busy);
        }

        this._renderTiles();
        this._renderCustom();
        this._syncItem.visible = st !== null && st.needsSync;
    }

    _renderTiles() {
        this._tiles.destroy_all_children();
        const st = this._status;
        if (!st)
            return;
        this._tiles.opacity = this._busy ? 110 : 255;

        for (let i = 0; i < st.platforms.length; i += TILE_COLUMNS) {
            const row = new St.BoxLayout({x_expand: true, style_class: 'social-switch-tile-row'});
            for (let c = 0; c < TILE_COLUMNS; c++) {
                const p = st.platforms[i + c];
                if (!p) {
                    row.add_child(new St.Widget({x_expand: true}));   // keeps columns equal
                    continue;
                }
                const tile = new St.Button({
                    label: shortLabel(p),
                    x_expand: true,
                    can_focus: true,
                    reactive: !this._busy,
                    track_hover: true,
                    style_class: `social-switch-tile social-switch-tile-${tileState(p)}`,
                });
                tile.connect('clicked', () => this._privileged(tileAction(p)));
                row.add_child(tile);
            }
            this._tiles.add_child(row);
        }
    }

    _renderCustom() {
        const sites = this._status?.custom ?? [];
        this._customMenu.visible = sites.length > 0;
        this._customMenu.label.text = `Custom sites (${sites.length}) - click to unblock`;
        this._customMenu.menu.removeAll();
        for (const site of sites) {
            const warn = site.status === 'blocked' ? '' : '  (needs re-apply)';
            const item = new PopupMenu.PopupMenuItem(`${site.domain}${warn}`);
            item.connect('activate', () => this._privileged(['on', site.domain]));
            this._customMenu.menu.addMenuItem(item);
        }
    }

    _setNote(text) {
        this._note = text;
        this._render();
    }

    _onMasterToggled(state) {
        // Two independent guards against a feedback loop (render -> toggled ->
        // CLI -> status change -> render ...): ignore changes we made ourselves,
        // and ignore any request that already matches the real state.
        if (this._updatingSwitch)
            return;
        const args = masterRequest(this._status, state);
        if (args)
            this._privileged(args);
    }

    _onDnsToggled(state) {
        if (this._updatingDns)
            return;
        const args = dnsRequest(this._dns, state);
        if (args)
            this._privileged(args, 'cloudflare-switch');
    }

    // ── talking to the CLI ──────────────────────────────────────────────────────
    refresh() {
        if (this._destroyed)
            return Promise.resolve();
        if (this._fetching) {
            this._pending = true;       // never run two status calls at once
            return Promise.resolve();
        }
        this._fetching = true;
        return (async () => {
            try {
                do {
                    this._pending = false;
                    await this._fetchOnce();
                } while (this._pending && !this._destroyed);
            } finally {
                this._fetching = false;
            }
        })();
    }

    async _fetchOnce() {
        const cli = findCli();
        this._cliMissing = cli === null;
        if (!cli) {
            this._status = null;
            this._note = 'Run install.sh from the social-switch-widget folder.';
            if (!this._destroyed)
                this._render();
            return;
        }
        const res = await run([cli, 'status', '--json'], this._cancellable);
        if (this._destroyed)
            return;
        await this._fetchDns();
        if (this._destroyed)
            return;
        const parsed = res.exit === 0 ? parseStatus(res.stdout) : null;
        if (parsed) {
            this._status = parsed;
            if (!this._busy)
                this._note = '';
        } else {
            this._status = null;
            this._note = lastErrorLine(res.stderr) || 'Unexpected output from social-switch.';
        }
        this._render();
    }

    async _fetchDns() {
        this._dns = null;
        if (!this._settings.get_boolean('show-dns-row'))
            return;
        const cf = findCli('cloudflare-switch');
        if (!cf)
            return;
        const res = await run([cf, 'status', '--json'], this._cancellable);
        this._dns = res.exit === 0 ? parseDnsStatus(res.stdout) : null;
    }

    async _privileged(args, tool = 'social-switch') {
        if (this._busy || this._destroyed)
            return;
        // Third line of defence against any toggled-signal storm: never start
        // two privileged actions within 1.5 s of each other.
        if (GLib.get_monotonic_time() < this._cooldownUntil)
            return;
        const cli = findCli(tool);
        if (!cli) {
            this._setNote(`${tool} is not installed.`);
            return;
        }
        this._busy = true;
        this._note = 'Waiting for authentication...';
        this._render();
        const failsafe = this._addTimer(BUSY_FAILSAFE_SECONDS, () => {
            this._busy = false;
            this._render();
        });

        const res = await run(['pkexec', cli, ...args], this._cancellable);
        if (this._destroyed)
            return;
        this._removeTimer(failsafe);
        this._busy = false;
        this._cooldownUntil = GLib.get_monotonic_time() + COOLDOWN_US;
        this._note = '';

        if (res.exit !== 0 && !isAuthCancelled(res.exit)) {
            const why = lastErrorLine(res.stderr) || `exit code ${res.exit}`;
            this._note = why;
            Main.notify('Social Switch', `Could not apply the change: ${why}`);
        }
        await this.refresh();
        this._render();
    }

    _addSite() {
        const host = normalizeSite(this._entry.get_text());
        if (!host) {
            this._setNote('That does not look like a website (try example.com).');
            return;
        }
        this._entry.set_text('');
        this._privileged(['off', host]);
    }

    // ── small plumbing ────────────────────────────────────────────────────────────
    _connect(obj, name, fn) {
        this._signals.push([obj, obj.connect(name, fn)]);
    }

    _addTimer(seconds, fn) {
        const id = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, seconds, () => {
            this._timers.delete(id);
            fn();
            return GLib.SOURCE_REMOVE;
        });
        this._timers.add(id);
        return id;
    }

    _removeTimer(id) {
        if (this._timers.delete(id))
            GLib.source_remove(id);
    }

    destroy() {
        this._destroyed = true;
        this._cancellable.cancel();
        this._timers.forEach(id => GLib.source_remove(id));
        this._timers.clear();
        this._signals.forEach(([obj, id]) => obj.disconnect(id));
        this._signals = [];
        super.destroy();
    }
});

export default class SocialSwitchExtension extends Extension {
    enable() {
        console.log(`social-switch ${BUILD} loaded (master-switch loop guards active)`);
        this._settings = this.getSettings();
        this._positionId = this._settings.connect('changed::panel-position', () => this._mount());
        this._mount();

        // Refresh the moment /etc/hosts changes (terminal use, another tool, ...).
        try {
            this._monitor = Gio.File.new_for_path('/etc')
                .monitor_directory(Gio.FileMonitorFlags.NONE, null);
            this._monitorId = this._monitor.connect('changed', (_m, file) => {
                if (file.get_basename() === 'hosts')
                    this._debounceRefresh();
            });
        } catch (e) {
            console.warn(`social-switch: cannot watch /etc (${e.message}); using the timer only`);
        }

        this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
            this._indicator?.refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._pollId) {
            GLib.source_remove(this._pollId);
            this._pollId = null;
        }
        if (this._debounceId) {
            GLib.source_remove(this._debounceId);
            this._debounceId = null;
        }
        if (this._monitor) {
            this._monitor.disconnect(this._monitorId);
            this._monitor.cancel();
            this._monitor = null;
        }
        if (this._positionId) {
            this._settings.disconnect(this._positionId);
            this._positionId = null;
        }
        this._unmount();
        this._settings = null;
    }

    _debounceRefresh() {
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        this._debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DEBOUNCE_MS, () => {
            this._debounceId = null;
            this._indicator?.refresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    _mount() {
        this._unmount();
        this._indicator = new SocialSwitchIndicator(this);
        const [index, box] = POSITIONS[this._settings.get_string('panel-position')] ?? POSITIONS.right;
        Main.panel.addToStatusArea(this.uuid, this._indicator, index, box);
    }

    _unmount() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
