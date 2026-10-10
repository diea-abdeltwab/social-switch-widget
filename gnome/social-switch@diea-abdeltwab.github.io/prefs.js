import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// Bind an Adw.ComboRow to a string GSettings key through a [value, label] table.
function addCombo(group, settings, {key, title, subtitle = '', options}) {
    const row = new Adw.ComboRow({
        title,
        subtitle,
        model: Gtk.StringList.new(options.map(([, label]) => label)),
    });
    const sync = () => {
        const index = options.findIndex(([value]) => value === settings.get_string(key));
        if (index >= 0 && row.selected !== index)
            row.selected = index;
    };
    sync();
    row.connect('notify::selected', () => {
        const [value] = options[row.selected];
        if (value !== settings.get_string(key))
            settings.set_string(key, value);
    });
    settings.connect(`changed::${key}`, sync);
    group.add(row);
}

export default class SocialSwitchPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage({
            title: 'Social Switch',
            icon_name: 'changes-prevent-symbolic',
        });
        window.add(page);

        const display = new Adw.PreferencesGroup({title: 'Display'});
        page.add(display);

        addCombo(display, settings, {
            key: 'panel-position',
            title: 'Position in the top bar',
            options: [['right', 'Right'], ['center', 'Next to the clock'], ['left', 'Left']],
        });

        const label = new Adw.SwitchRow({
            title: 'Show ON / OFF next to the icon',
            subtitle: 'ON = social media allowed, OFF = blocked, 4/12 = some platforms blocked',
        });
        settings.bind('show-label', label, 'active', Gio.SettingsBindFlags.DEFAULT);
        display.add(label);

        const dns = new Adw.SwitchRow({
            title: 'Show the DNS filter switch',
            subtitle: 'Adds a Cloudflare DNS filter (family / malware / standard) row to the popup. ' +
                'Uses the cloudflare-switch tool; choose the preset in a terminal: cloudflare-switch on malware',
        });
        settings.bind('show-dns-row', dns, 'active', Gio.SettingsBindFlags.DEFAULT);
        display.add(dns);

        const about = new Adw.PreferencesGroup({
            title: 'How it works',
            description: 'This extension is only a front end for the social-switch command. ' +
                'Every change asks for your password through polkit, and the command edits ' +
                '/etc/hosts. Run "social-switch doctor" in a terminal if something looks wrong.',
        });
        page.add(about);
    }
}
