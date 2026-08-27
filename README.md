[![social-switch-widget banner](https://capsule-render.vercel.app/api?type=waving&color=0:111214,100:5A1A1F&height=210&section=header&text=social-switch-widget&fontSize=42&fontColor=EDEDEC&animation=fadeIn&fontAlignY=36&desc=An%20Omarchy%20bar%20widget%20for%20social-switch%20%E2%80%94%20tap%20a%20platform%2C%20it%20flips&descAlignY=55&descColor=C99BA0&descSize=16)](https://capsule-render.vercel.app)

[![Typing SVG](https://readme-typing-svg.herokuapp.com/?font=Fira+Code&weight=600&size=20&duration=3000&pause=800&color=EDEDEC&background=00000000&center=true&vCenter=true&width=650&lines=Tap+a+platform%2C+it+flips.+That's+the+whole+model.;Global+switch+%3D+bulk+action%2C+not+a+persistent+mode.;Real+mixed-state+indicator%2C+not+a+misleading+snap.;Polkit-scoped+to+one+script.+Not+a+sudoers+rule.)](https://git.io/typing-svg)

[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/) [![QML](https://img.shields.io/badge/QML%20%2F%20Quickshell-41CD52?style=for-the-badge&logo=qt&logoColor=white)](https://quickshell.outfoxxed.me/) [![Omarchy](https://img.shields.io/badge/Omarchy%204%20%22Quattro%22-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://omarchy.org/) [![License](https://img.shields.io/badge/License-MIT-7A2E33?style=for-the-badge)](https://github.com/diea-abdeltwab/social-switch-widget/blob/main/LICENSE)

---

## 📖 About

**social-switch-widget** wraps [`social-switch`](https://github.com/diea-abdeltwab/media-switches) — the `/etc/hosts`-based social media blocker from [`media-switches`](https://github.com/diea-abdeltwab/media-switches) — in an Omarchy 4 ("Quattro") bar widget. A small `ON`/`OFF` icon opens a popup with a global switch and a tap-to-block grid, one tile per platform. No terminal, no remembering flags.

Every platform is simply **blocked** or **allowed** — there's no separate "exclude" concept layered on top of a global mode. Tap a tile, it flips, full stop.

---

## 🖼️ Preview

<table>
<tr>
<td align="center"><img src="screenshots/all-allowed.png" width="210"><br><sub><b>All allowed</b></sub></td>
<td align="center"><img src="screenshots/all-blocked.png" width="210"><br><sub><b>All blocked</b></sub></td>
<td align="center"><img src="screenshots/mixed-10-12.png" width="210"><br><sub><b>Mixed — 10/12</b></sub></td>
<td align="center"><img src="screenshots/mixed-4-12.png" width="210"><br><sub><b>Mixed — 4/12</b></sub></td>
</tr>
</table>

The bar icon reads `ON` when nothing's blocked and `OFF` when anything is — same word, same meaning, in both the icon and the popup, on purpose.

---

## ✨ Features

- 🟢🔴 **Tap-to-toggle grid** — every platform is independently blocked (red) or allowed (green); tapping a tile flips just that one
- 🎚️ **Bulk global switch** — `ON` sets every platform to allowed, `OFF` sets every platform to blocked, regardless of individual state a second ago
- 🌗 **Genuine mixed-state indicator** — block one platform out of twelve and the switch shows a real partial position (orange, thumb centered) instead of snapping to a misleading full ON/OFF
- 🔐 **Polkit, scoped** — every toggle asks for your password via a dedicated `pkexec` action bound to this one script, not a blanket sudoers rule
- 💾 **Single source of truth** — `/etc/social-switch/blocked` is authoritative; `/etc/hosts` is a reflection of it, so nothing can drift out of sync
- ⚡ **No redundant polling** — status is fetched once by the bar icon and pushed into the popup; the popup never runs its own second poll

---

## 📦 Requirements

- Omarchy **4.x ("Quattro")** — provides the Quickshell bar this widget loads into
- `polkit` (`pkexec`) — for privileged block/unblock/on/off actions
- `bash`, `awk`, `grep` — the CLI itself

```bash
# Arch / Omarchy
sudo pacman -S polkit
```

---

## 🚀 Installation

```bash
# 1. Clone the repo
git clone https://github.com/diea-abdeltwab/social-switch-widget.git
cd social-switch-widget

# 2. Run the installer
chmod +x install.sh
./install.sh
```

The installer checks dependencies, backs up anything it's about to overwrite, lets you pick a bar section (left/center/right), installs the CLI + polkit policy + plugin, validates the plugin (`omarchy plugin validate`, `qmllint`) before enabling it, and reloads the shell live — no restart needed.

```bash
# Uninstall
./uninstall.sh
```
Removes the plugin and polkit policy; asks separately whether to remove the CLI too, unblocking everything first if needed.

---

## 🎬 Usage

**From the bar:** click the icon to open the popup, click the switch to block/allow everything, tap any tile to flip just that platform.

**From the terminal**, the underlying CLI works exactly the same way:

```bash
social-switch status                 # per-platform table, no root needed
social-switch status --json          # same, machine-readable
social-switch list                   # every platform key

sudo social-switch on                # allow everything
sudo social-switch off               # block everything
sudo social-switch off --except discord,twitch   # block everything except a couple

sudo social-switch block reddit      # block just Reddit
sudo social-switch unblock reddit    # allow it again

social-switch doctor                 # duplicate /etc/hosts entries, DNS-over-HTTPS bypass check
```

**Platforms tracked:** YouTube, Facebook, Instagram, Threads, X/Twitter, TikTok, Reddit, Snapchat, Pinterest, Kick, Discord, Twitch. Edit `PLATFORM_DOMAINS` near the top of `bin/social-switch` to add, remove, or re-scope any of them.

---

## 🏗️ Architecture

```
                 ┌────────────────────────────┐
   bar icon ──▶  │  plugin/Widget.qml         │  polls status every 20s
                 │  - owns the status Process │  via `social-switch status --json`
                 │  - Loader → Panel.qml      │
                 └───────────────┬────────────┘
                                 │ injects bar / anchorItem / hostWidget
                                 ▼
                 ┌────────────────────────────┐
                 │  plugin/Panel.qml          │  popup: switch + platform grid;
                 │  - KeyboardPanel/          │  asks hostWidget.refresh() after
                 │    PanelKeyCatcher         │  any pkexec action
                 └───────────────┬────────────┘
                                 │ pkexec (per privileged action)
                                 ▼
                 ┌────────────────────────────┐
                 │  bin/social-switch         │  root, via pkexec —
                 │  (bash)                    │  BLOCKED_FILE is the
                 └───────────────┬────────────┘  single source of truth
                                 ▼
                          /etc/hosts (managed block)
                        /etc/social-switch/blocked
```

**File naming note:** the plugin entry point is `Widget.qml`, not `BarWidget.qml` as the official Omarchy plugin guide names it — naming it identically to the `BarWidget` type it instantiates caused a "File name case mismatch" load failure on this system. Same root element, different filename.

---

## 🔐 Privilege model

Every toggle prompts for your password via `pkexec`, scoped to `/usr/local/bin/social-switch` specifically through a dedicated polkit action — not a sudoers `NOPASSWD` rule, which would mean *no* authentication ever, from any process able to invoke sudo as you, for as long as the rule exists.

The polkit action grants "run this exact binary as root with any arguments," not "run only valid subcommands with valid platform names" — that argument-level enforcement lives inside the script itself (`require_root`, `is_valid_platform`), since polkit action definitions can't express it directly.

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
<summary><strong>Sites still load even though the widget shows "blocked"</strong></summary>
<br>

Browsers with Secure DNS / DNS-over-HTTPS bypass `/etc/hosts` entirely. Run `social-switch doctor` for a full diagnosis, or disable Secure DNS in the browser.
</details>

---

## 🗂️ Project Structure

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

## 🧭 Roadmap

- [ ] Optional per-platform schedule (e.g. auto-block during work hours)
- [ ] Config-driven platform list instead of editing the script directly
- [ ] A settings row in the popup for quick section/position changes

---

## 🤝 Contributing

Issues and PRs welcome — especially reports of Quickshell/QML behavior on Omarchy versions or configs this hasn't been tested against yet.

---

## 📜 License

Released under the [MIT License](LICENSE) — same as [`media-switches`](https://github.com/diea-abdeltwab/media-switches).

---

### 👤 Author

**Diea Abdeltwab** — Data Engineer · Software Engineer

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/diea-abdeltwab/) [![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/diea-abdeltwab) [![Email](https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:dieaabdeltwab2024@gmail.com)

[![social-switch-widget footer](https://capsule-render.vercel.app/api?type=waving&color=0:5A1A1F,100:111214&height=100&section=footer)](https://capsule-render.vercel.app)
