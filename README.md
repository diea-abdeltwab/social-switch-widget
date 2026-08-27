# 🔒 social-switch-widget

### *A bar icon and popup for [`social-switch`](https://github.com/diea-abdeltwab/media-switches) — block or allow each platform with a tap, no terminal required.*

[![Made with QML](https://img.shields.io/badge/Made%20with-QML%20%2F%20Quickshell-4EAA25?style=for-the-badge&logo=qt&logoColor=white)](https://quickshell.outfoxxed.me/) [![Platform](https://img.shields.io/badge/Platform-Omarchy%204%20%22Quattro%22-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://omarchy.org/) [![License](https://img.shields.io/badge/License-MIT-a6e3a1?style=for-the-badge)](#-license)

---

## 📌 About

**social-switch-widget** wraps the [`social-switch`](https://github.com/diea-abdeltwab/media-switches) CLI in an Omarchy 4 bar widget: a small `ON`/`OFF` icon that opens a popup with a global switch and a tap-to-block grid for every platform. No `sudo social-switch off --except ...` to type — just tap.

- 🟢🔴 **Every platform is just blocked or allowed** — no separate "exclude" concept layered on top. Tap a tile, it flips. That's the whole model.
- 🎚️ **Global switch is a bulk action, not a mode** — `ON` sets everything to allowed, `OFF` sets everything to blocked, regardless of whatever individual state things were in a second ago.
- 🌗 **Real mixed-state indicator** — block one platform out of twelve and the switch shows a genuine partial position instead of misleadingly snapping to a full ON/OFF.
- 🔐 **Polkit, not sudoers** — every toggle asks for your password, scoped to this one script specifically, not a blanket "run anything as root" rule.
- 💾 **Single source of truth** — `/etc/social-switch/blocked` is what's authoritative; `/etc/hosts` is just a reflection of it, so there's nothing to drift out of sync.

---

## 🖼️ Screenshots

<table>
<tr>
<td align="center"><img src="screenshots/all-allowed.png" width="220"><br><sub><b>All allowed</b></sub></td>
<td align="center"><img src="screenshots/all-blocked.png" width="220"><br><sub><b>All blocked</b></sub></td>
<td align="center"><img src="screenshots/mixed-10-12.png" width="220"><br><sub><b>Mixed — 10/12</b></sub></td>
<td align="center"><img src="screenshots/mixed-4-12.png" width="220"><br><sub><b>Mixed — 4/12</b></sub></td>
</tr>
</table>

The bar icon at the top reads `ON` when nothing's blocked and `OFF` when anything is — same word, same meaning, in both the icon and the popup, on purpose (an earlier version didn't agree with itself here, which was more confusing than it sounds).

---

## 📦 Installation

```bash
git clone https://github.com/diea-abdeltwab/social-switch-widget.git
cd social-switch-widget
chmod +x install.sh
./install.sh
```

The installer checks dependencies, backs up anything it's about to touch, lets you pick which bar section to use, installs the CLI + polkit policy + plugin, validates the plugin before enabling it, and reloads the shell live — no restart needed. Full walkthrough and every troubleshooting step below.

### Uninstall

```bash
./uninstall.sh
```

Removes the plugin and polkit policy; asks separately whether to remove the CLI too (unblocking everything first if needed, so you're never left with a permanent block and nothing to undo it).

---

## ⚙️ How blocking works

Each platform is independently `blocked` or `allowed` — full stop. There's no global "mode" layered on top of that:

| Action | Effect |
|---|---|
| Tap a platform tile | Flips **just that one**, whatever the rest are doing |
| Global switch → `ON` | Sets **every** platform to allowed |
| Global switch → `OFF` | Sets **every** platform to blocked |
| `sudo social-switch block <platform>` | Same as tapping a tile, from the terminal |
| `sudo social-switch unblock <platform>` | Same as tapping it again |
| `sudo social-switch off --except a,b` | Block everything except a couple of names |

```bash
social-switch status                 # per-platform table, no root
social-switch status --json          # same, machine-readable
social-switch list                   # every platform key
sudo social-switch on                # allow everything
sudo social-switch off               # block everything
sudo social-switch block reddit      # block just Reddit
sudo social-switch unblock reddit    # allow it again
social-switch doctor                 # duplicate entries / DNS-over-HTTPS bypass check
```

### Platforms tracked

YouTube, Facebook, Instagram, Threads, X/Twitter, TikTok, Reddit, Snapchat, Pinterest, Kick, Discord, Twitch — edit `PLATFORM_DOMAINS` near the top of `bin/social-switch` to add, remove, or change domains for any of them.

---

## 🏗️ Architecture

```
                 ┌────────────────────────────┐
   bar icon ──▶  │  plugin/Widget.qml          │  polls status every 20s
                 │  - owns the status Process   │  via `social-switch status --json`
                 │  - Loader → Panel.qml        │
                 └──────────────┬──────────────┘
                                 │ injects bar / anchorItem / hostWidget
                                 ▼
                 ┌────────────────────────────┐
                 │  plugin/Panel.qml            │  popup: switch + platform grid;
                 │  - KeyboardPanel/            │  asks hostWidget.refresh() after
                 │    PanelKeyCatcher           │  any pkexec action
                 └──────────────┬──────────────┘
                                 │ pkexec (per privileged action)
                                 ▼
                 ┌────────────────────────────┐
                 │  bin/social-switch            │  root, via pkexec —
                 │  (bash)                       │  BLOCKED_FILE is the
                 └──────────────┬──────────────┘  single source of truth
                                 ▼
                          /etc/hosts (managed block)
                        /etc/social-switch/blocked
```

Status is fetched in exactly one place (`Widget.qml`'s own `Process`) and pushed into the popup — the popup never runs a second, redundant poll of its own. The QML never touches `/etc/hosts` or root state directly; it only shells out to the same CLI you'd run yourself, either unprivileged (`status --json`) or via `pkexec` (`on`, `off`, `block`, `unblock`).

**File naming note:** the plugin entry point is `Widget.qml`, not `BarWidget.qml` as the official Omarchy plugin guide names it — naming it identically to the `BarWidget` type it instantiates caused a "File name case mismatch" load failure on this system. Same root element, different filename.

---

## 🔐 Privilege model

Every toggle prompts for your password via `pkexec`, scoped to `/usr/local/bin/social-switch` specifically through a dedicated polkit action — not a sudoers `NOPASSWD` rule, which would mean *no* authentication ever, from any process that can invoke sudo as you, for as long as the rule exists.

**Trade-off worth knowing:** the polkit action grants "run this exact binary as root with any arguments," not "run only `on`/`off`/`block|unblock <valid-key>`." That argument-level enforcement lives inside the script itself (`require_root`, `is_valid_platform`) — polkit action definitions can't express it directly.

---

## 🩺 Troubleshooting

<details>
<summary><strong>Icon doesn't appear on the bar</strong></summary>
<br>

Check `omarchy plugin list` shows `diea.social-switch` as enabled, and that it appears somewhere under `bar.layout` in `~/.config/omarchy/shell.json`. If it's there but nothing renders, force a full restart (`omarchy-restart-shell`), then check `qs log -p "$OMARCHY_PATH/shell" --tail 100` for anything mentioning `social-switch`, `Widget.qml`, or `Panel.qml`.
</details>

<details>
<summary><strong>Log shows "File name case mismatch"</strong></summary>
<br>

`install.sh` wipes the plugin directory before copying fresh files in, specifically to prevent a stale file from an earlier version tripping this. If it still happens:
```bash
rm -rf ~/.config/omarchy/plugins/diea.social-switch ~/.cache/quickshell ~/.cache/qmlcache
./install.sh
```
</details>

<details>
<summary><strong>Toggle does nothing / no polkit prompt appears</strong></summary>
<br>

Test the privileged path directly, outside the widget:
```bash
pkexec /usr/local/bin/social-switch off --except discord
```
If that works but the bar doesn't, check `qs log` for errors from the `privProc` Process in `Panel.qml`.
</details>

<details>
<summary><strong>Excluding a platform during an active block takes a few seconds to show</strong></summary>
<br>

`/etc/hosts` and the OS DNS cache update immediately — the browser's own DNS cache doesn't know that and typically caches the negative result independently for a short while. Not something the script can flush from outside the browser process; a hard refresh or a few seconds clears it.
</details>

<details>
<summary><strong>Sites still load even though the widget shows "blocked"</strong></summary>
<br>

Browsers with Secure DNS / DNS-over-HTTPS bypass `/etc/hosts` entirely. Run `social-switch doctor` for a full diagnosis, or disable Secure DNS in the browser.
</details>

---

## 🏗️ Project Structure

```
social-switch-widget/
├── bin/
│   └── social-switch                  # CLI (root-owned once installed) + status --json
├── plugin/
│   ├── manifest.json                   # entryPoints.barWidget → Widget.qml
│   ├── Widget.qml                       # bar icon; owns the status Process; loads Panel.qml
│   └── Panel.qml                         # popup content (switch + platform grid)
├── polkit/
│   └── com.diea.socialswitch.policy    # pkexec action, scoped to the CLI
├── screenshots/
├── install.sh                          # installer (validates before enabling)
├── uninstall.sh                        # clean removal
└── README.md
```

---

## 📜 License

MIT — same as [`media-switches`](https://github.com/diea-abdeltwab/media-switches). See [`LICENSE`](LICENSE).

## 🧑‍💻 About the author

**Diea Abdeltwab** — Data Engineer · Software Engineer · Cairo, Egypt 🇪🇬

*Turning raw data into reliable systems — and, on the side, building the local-first tools I actually want to use.*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/diea-abdeltwab/) [![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/diea-abdeltwab) [![Email](https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:dieaabdeltwab2024@gmail.com)

⭐ **If this saves you from tapping through your own hosts file, a star helps a lot!** ⭐
