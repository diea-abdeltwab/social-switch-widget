[![social-switch GNOME banner](https://capsule-render.vercel.app/api?type=waving&color=0:111214,100:5A1A1F&height=210&section=header&text=social-switch%20%C2%B7%20GNOME&fontSize=42&fontColor=EDEDEC&animation=fadeIn&fontAlignY=36&desc=Block%20or%20allow%20social%20media%20from%20the%20GNOME%20top%20bar&descAlignY=55&descColor=C99BA0&descSize=16)](https://capsule-render.vercel.app)

[![Typing SVG](https://readme-typing-svg.herokuapp.com/?font=Fira+Code&weight=600&size=20&duration=3000&pause=800&color=EDEDEC&background=00000000&center=true&vCenter=true&width=650&lines=Tap+a+platform%2C+it+flips.;Native+polkit+prompt+from+GNOME+Shell.;Updates+the+moment+/etc/hosts+changes.;No+blocking+logic+in+JavaScript.)](https://git.io/typing-svg)

[![GNOME Shell](https://img.shields.io/badge/GNOME%20Shell-45%20%E2%80%93%2050-4A86CF?style=for-the-badge&logo=gnome&logoColor=white)](https://www.gnome.org/) [![GJS](https://img.shields.io/badge/GJS-ES%20modules-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black)](https://gjs.guide/) [![Bash](https://img.shields.io/badge/CLI-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](../core/social-switch) [![License](https://img.shields.io/badge/License-MIT-7A2E33?style=for-the-badge)](../LICENSE)

---

## 📖 About

A GNOME Shell extension for [`social-switch`](../core/social-switch). A lock icon sits in the top bar; its popup has a master switch and one tile per platform. Tap a tile and that platform flips between **blocked** (red) and **allowed** (green).

The extension is deliberately thin. It reads `social-switch status --json` and runs `pkexec social-switch …` — all blocking logic stays in the Bash tool, which you can also use from a terminal at any time. The same tool backs the [Omarchy widget](../omarchy-quatto), so the two never disagree.

Vocabulary, everywhere: **ON = social media allowed · OFF = blocked**.

---

## 🖼️ Preview

<table>
<tr>
<td align="center"><img src="screenshots/gnome-all-allowed.png" width="260"><br><sub><b>All allowed</b><br>green tiles, open lock, <code>ON</code></sub></td>
<td align="center"><img src="screenshots/gnome-mixed-6-12.png" width="260"><br><sub><b>Mixed</b><br>6 of 12 blocked, <code>6/12</code></sub></td>
</tr>
<tr>
<td align="center"><img src="screenshots/gnome-mixed-11-12.png" width="260"><br><sub><b>Almost everything blocked</b><br>11 of 12, tap one tile to free it</sub></td>
<td align="center"><img src="screenshots/gnome-all-blocked.png" width="260"><br><sub><b>All blocked</b><br>red tiles, closed lock, <code>OFF</code></sub></td>
</tr>
</table>

The panel icon is a lock: green open lock = everything allowed, red closed lock = everything blocked, amber = mixed (`6/12`), orange warning = a block is missing from `/etc/hosts` and needs re-applying. The master switch reads *on* only when everything is blocked; from a mixed state it blocks the rest.

---

## ✨ Features

- 🟢🔴 **Tap-to-toggle tiles** — every platform is independently blocked or allowed
- 🎚️ **Master switch** — blocks or allows everything at once; shows a real *mixed* state (`4/12`) instead of pretending
- 🌐 **Any website** — type `example.com` (or paste a full URL) in the popup to block it; custom sites are listed and unblocked with one click
- 🔐 **Native polkit prompt** — GNOME Shell's own authentication dialog, scoped to one script via a dedicated polkit action (no sudoers rule)
- ⚡ **Live updates** — watches `/etc/hosts`, so changes made from a terminal appear immediately; a 60 s timer is the fallback
- 🩹 **Self-healing hint** — if another tool rewrites `/etc/hosts` and wipes the blocks, the icon turns to a warning and the popup offers **Re-apply saved blocks**
- 🧱 **No overlapping calls** — status requests are queued, never run twice at once, and clicks are ignored while an action is in flight
- 🛡️ **Loop-proof switches** — GNOME 50 re-announces a switch's state when code sets it; the extension ignores its own updates and any request that already matches reality, and enforces a short cool-down between actions
- 🌐 **Optional DNS-filter switch** — turn the Cloudflare DNS filter (`cloudflare-switch`) on/off from the same popup; hidden by default (enable it in Preferences)
- 🧩 **Works with `cloudflare-switch`** — independent layers, no shared files (see the [root README](../README.md#-how-the-three-tools-stay-out-of-each-others-way))

---

## 📦 Requirements

- **GNOME Shell 45 – 50** (Fedora 39+, Ubuntu 24.04+, Debian 13, Arch, openSUSE Tumbleweed …)
- `polkit` (`pkexec`) — usually already installed on any GNOME system
- `bash` ≥ 4.4, `awk`, `flock`, `glib-compile-schemas`

```bash
# Fedora
sudo dnf install polkit glib2-devel

# Debian / Ubuntu  (pkexec; on older releases the package is policykit-1)
sudo apt install pkexec libglib2.0-bin

# Arch
sudo pacman -S polkit glib2
```

> **Immutable distros** (Silverblue, Kinoite): `/usr/share/polkit-1/actions` is read-only there, so the polkit policy can't be installed and the extension can't ask for a password. Use the CLI directly with `sudo`, or layer the policy into the image with `rpm-ostree`.

---

## 🚀 Installation

```bash
git clone https://github.com/diea-abdeltwab/social-switch-widget.git
cd social-switch-widget
./install.sh
```

One command. It asks for your sudo password once, then:

1. installs `social-switch`, `cloudflare-switch` and the polkit policies from [`../core`](../core) (refusing to silently downgrade a newer script);
2. builds the extension — settings schema compiled and verified — in a staging folder and moves it into `~/.local/share/gnome-shell/extensions/` in one step, so GNOME Shell never sees a half-installed extension;
3. removes **older copies of the scripts that would hide the new ones** (e.g. `~/.local/bin/social-switch`, `/usr/local/sbin/social-switch`);
4. re-applies your saved blocks, so nothing you had blocked is lost.

**Then log out and back in once.** GNOME Shell loads extension code once per session, so a freshly installed or updated extension is only picked up after that. Enable it in the *Extensions* app, or:

```bash
gnome-extensions enable social-switch@diea-abdeltwab.github.io
```

Check which build is running:

```bash
journalctl --user -b --no-pager | grep "social-switch 1.1"      # "social-switch 1.1.0 loaded …"
gnome-extensions info social-switch@diea-abdeltwab.github.io | grep -E "Version|State"
```

Other ways in: `./install.sh --yes` (no questions) · `--no-cloudflare` (skip `cloudflare-switch`) · `gnome/install.sh` alone installs just the extension (plus the CLIs unless `--skip-core`).

```bash
./cleanup.sh        # remove leftovers of earlier installs / experiments
./uninstall.sh      # remove the extension; asks before removing the CLIs
```

Removing the CLIs always **unblocks everything and turns the DNS filter off first**, so uninstalling can never leave `/etc/hosts` locked.

---

## 🎬 Usage

**From the top bar:** click the lock → switch = block/allow everything · tile = flip one platform · text box = block any site · *Custom sites* = click an entry to unblock it.

**Preferences** (`gnome-extensions prefs social-switch@diea-abdeltwab.github.io`): position in the bar (right / next to the clock / left), whether to show the `ON` / `OFF` / `6/12` text, and the optional **DNS filter switch** (a row that turns the Cloudflare DNS filter on/off; pick the preset in a terminal with `sudo cloudflare-switch on malware`).

**From a terminal**, the same tool:

```bash
social-switch status                    # table, no root needed
sudo social-switch off youtube kick     # block two platforms
sudo social-switch on                   # allow everything
sudo social-switch off example.com      # block any site (URLs are fine)
social-switch doctor                    # duplicate entries, DNS-over-HTTPS check, resolver check
```

---

## 🏗️ Architecture

```
                 ┌──────────────────────────────────┐
   top-bar lock  │ extension.js                     │  status: social-switch status --json
   + popup       │  SocialSwitchIndicator           │  (no privileges, queued, never overlapping)
                 │  - Gio.FileMonitor on /etc/hosts │
                 │  - 60 s timer fallback           │
                 └───────────────┬──────────────────┘
                                 │ pkexec social-switch <on|off|sync> …   (GNOME Shell's polkit agent asks)
                                 ▼
                 ┌──────────────────────────────────┐
                 │ /usr/local/bin/social-switch     │  root; /etc/social-switch/blocked is the
                 │ (bash, shared with every front   │  single source of truth
                 │  end, see ../core)               │
                 └───────────────┬──────────────────┘
                                 ▼
                          /etc/hosts (managed block)

   socialLogic.js — pure functions (parse, labels, URL normalising); unit-tested with Node
```

Design notes:

- **Pure logic is separate.** `socialLogic.js` imports nothing from GNOME, so `node --test` can check it against real CLI output.
- **No second source of truth.** The extension never edits `/etc/hosts`; it cannot drift from the CLI.
- **Root-owned path only.** The extension runs the CLI as root, so it only looks in `/usr/local/bin` and `/usr/bin` — never `~/.local/bin`, which anything running as you could modify.

---

## 🔐 Privilege model

Every change goes through `pkexec`, bound to one absolute path per tool by a polkit action — `com.diea.socialswitch.run` for `/usr/local/bin/social-switch`, `com.diea.cloudflareswitch.run` for `/usr/local/bin/cloudflare-switch` (`auth_admin_keep`: one password covers a short grace window, so tapping a tile and then the switch doesn't prompt twice).

The action grants "run this exact script as root", not "run only valid arguments" — argument checking (platform keys, hostnames, option-looking input) lives in the script. Extension input is passed as separate arguments, never through a shell.

---

## 🩺 Troubleshooting

<details>
<summary><strong>The icon doesn't appear</strong></summary>
<br>

Restart GNOME Shell once (log out/in on Wayland), then `gnome-extensions list | grep social` and `gnome-extensions enable social-switch@diea-abdeltwab.github.io`. Errors show up in:

```bash
journalctl -f -o cat /usr/bin/gnome-shell
```
</details>

<details>
<summary><strong>"Schema … could not be found" in the Shell log</strong></summary>
<br>

The settings schema wasn't compiled when GNOME tried to enable the extension. Re-run `./install.sh` (it now builds and verifies the schema before moving the extension into place), then log out and in. Manual check:

```bash
D=~/.local/share/gnome-shell/extensions/social-switch@diea-abdeltwab.github.io
gsettings --schemadir $D/schemas list-keys org.gnome.shell.extensions.social-switch
```
</details>

<details>
<summary><strong><code>sudo social-switch</code> behaves differently from the extension</strong></summary>
<br>

`sudo` searches `/usr/local/sbin` before `/usr/local/bin` on Fedora, so an old copy there wins. `./install.sh` and `./cleanup.sh` remove such copies; check with `sudo bash -c 'type -a social-switch'` and `sudo social-switch version` (should be 2.2.x).
</details>

<details>
<summary><strong>The popup says "social-switch is not installed"</strong></summary>
<br>

The CLI must be in `/usr/local/bin` or `/usr/bin`. Run `./install.sh` again, or `../core/install-core.sh`.
</details>

<details>
<summary><strong>No password prompt appears</strong></summary>
<br>

Test the privileged path outside the extension:

```bash
pkexec /usr/local/bin/social-switch off kick
```

If this fails, the polkit policy is missing (`ls /usr/share/polkit-1/actions/com.diea.socialswitch.policy`) or no polkit agent is running — GNOME Shell provides one in a normal session.
</details>

<details>
<summary><strong>Sites still load although they show as blocked</strong></summary>
<br>

Browsers with Secure DNS / DNS-over-HTTPS ignore `/etc/hosts`. Turn it off in the browser, then run `social-switch doctor`. Browsers installed as Flatpak/Snap read the host's `/etc/hosts` too, but their own DoH setting is separate.
</details>

<details>
<summary><strong>The icon shows a warning triangle</strong></summary>
<br>

Something rewrote `/etc/hosts` and removed blocks you asked for. Use **Re-apply saved blocks** in the popup, or `sudo social-switch sync`.
</details>

<details>
<summary><strong>Another program can't edit /etc/hosts</strong></summary>
<br>

While anything is blocked, `social-switch` makes `/etc/hosts` immutable (`chattr +i`) so other tools can't undo the blocks. To opt out, put `LOCK_HOSTS=no` in `/etc/social-switch/config`.
</details>

---

## 🗂️ Project Structure

```
gnome/
├── social-switch@diea-abdeltwab.github.io/
│   ├── metadata.json                    # GNOME 45–50
│   ├── extension.js                     # indicator, popup, CLI calls, file monitor
│   ├── socialLogic.js                   # pure logic (unit-tested)
│   ├── prefs.js                         # Adw preferences window
│   ├── stylesheet.css
│   └── schemas/…gschema.xml             # panel-position, show-label, show-dns-row
├── tests/socialLogic.test.mjs
├── screenshots/                        # the images used in this README
├── install.sh
├── uninstall.sh
└── README.md
```

---

## 🧭 Roadmap

- [x] `cloudflare-switch` on/off switch in the popup (opt-in)
- [ ] Choose the DNS preset (family / malware / standard) from the popup
- [ ] Quick Settings tile as an alternative to the top-bar button
- [ ] Notification when a block is lost and re-applied

---

## 🤝 Contributing

Issues and PRs welcome — please include your GNOME Shell version (`gnome-shell --version`) and the Shell log lines from the troubleshooting section.

---

## 📜 License

[MIT](../LICENSE)

---

### 👤 Author

**Diea Abdeltwab** — Data Engineer · Software Engineer

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/diea-abdeltwab/) [![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/diea-abdeltwab) [![Email](https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:dieaabdeltwab2024@gmail.com)

[![footer](https://capsule-render.vercel.app/api?type=waving&color=0:5A1A1F,100:111214&height=100&section=footer)](https://capsule-render.vercel.app)
