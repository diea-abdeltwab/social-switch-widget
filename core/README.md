# core — the two command-line tools

Everything else in this repository is a front end for these. They need only **Bash ≥ 4.4** and standard tools, and work on any Linux.

```bash
./install-core.sh              # /usr/local/bin/{social-switch,cloudflare-switch} + polkit policies
./install-core.sh --no-cloudflare --no-polkit --prefix /opt/tools
./uninstall-core.sh            # unblocks + turns the filter off, then removes
```

The installer shows the right package command for your distro (`dnf`, `apt`, `pacman`, `zypper`, `apk`, `xbps`), installs one polkit action per tool, asks before replacing a *newer* version with an older one, and warns when another copy elsewhere (including `/usr/local/sbin`, which `sudo` searches first) would hide the new one. It creates no backup files.

---

## social-switch (v2.2)

Blocks social media system-wide by writing a clearly marked block into `/etc/hosts` (`0.0.0.0` and `::` for every domain, with and without `www.`).

```bash
social-switch status [--json]        # no root needed
sudo social-switch off youtube kick  # block these
sudo social-switch on instagram      # allow it again
sudo social-switch off               # block all 12      (--except discord,twitch to spare some)
sudo social-switch on                # allow all 12
sudo social-switch off example.com   # any site; https://www.example.com/path works too
sudo social-switch sync              # re-apply the saved state
social-switch doctor                 # diagnose
```

**Platforms:** YouTube, Facebook, Instagram, Threads, X/Twitter, TikTok, Reddit, Snapchat, Pinterest, Kick, Discord, Twitch.

**Wording:** `on` = social media ON (allowed) · `off` = OFF (blocked).

### How it stays correct

- `/etc/social-switch/blocked` (and `custom`) is the **single source of truth**; `/etc/hosts` is a reflection of it. If another tool rewrites `/etc/hosts`, `status` reports the platform as `broken` and `sync` repairs it.
- Edits are atomic (temp file in `/etc`, then `mv`), serialised with `flock`, and keep ownership, mode and the **SELinux label** of the original file (matters on Fedora/RHEL).
- Only lines made *entirely* of managed domains are ever removed from `/etc/hosts`. Your own entries are untouched.
- While something is blocked, `/etc/hosts` is made immutable (`chattr +i`). Opt out with `LOCK_HOSTS=no` in `/etc/social-switch/config`.

### `status --json` (schema 2)

```json
{"schema":2,"version":"2.2.0","state":"off","mode":"mixed",
 "blocked_count":2,"wanted_count":2,"total":12,"immutable":false,
 "platforms":[{"key":"youtube","label":"YouTube","blocked":true,"wanted":true,"status":"blocked"}, …],
 "custom":[{"domain":"example.com","blocked":true,"status":"blocked"}]}
```

| field | meaning |
|---|---|
| `state` | legacy two-value view: `off` as soon as *any* platform is blocked (what the bar icon reads) |
| `mode` | `on` (none wanted blocked) · `mixed` · `off` (all blocked) |
| `wanted` / `blocked` | what you asked for / what `/etc/hosts` really contains |
| `status` | `allowed` · `blocked` · `broken` (wanted but missing → `sync`) · `external` (blocked by an entry we don't manage) |

### Upgrading from older builds

- Platforms that older builds shipped but this one doesn't (**Messenger**, **Tumblr**) are migrated to custom sites on first run, so they stay blocked. `social-switch on messenger` still works.
- Old state files are rewritten in the current format on the next `sync` or change.

---

## cloudflare-switch (v2.0)

Turns a Cloudflare DNS filter on or off for the whole machine.

```bash
cloudflare-switch status [--json|--short]
sudo cloudflare-switch on                 # family: 1.1.1.3 / 1.0.0.3 (malware + adult content)
sudo cloudflare-switch on malware         # 1.1.1.2 / 1.0.0.2
sudo cloudflare-switch on standard        # 1.1.1.1 / 1.0.0.1
sudo cloudflare-switch off                # back to the DNS you had
sudo cloudflare-switch sync               # re-apply (e.g. after adding a new Wi-Fi profile)
cloudflare-switch doctor
```

`enable` / `disable` are aliases. Here `on` means the filter is **active** — the opposite habit of `social-switch`.

### Backends (auto-detected)

| Backend | Used when | What it changes |
|---|---|---|
| `nm` | NetworkManager is running (Fedora, Ubuntu, Debian, Mint … desktops) | `ipv4.dns` / `ipv6.dns` + `ignore-auto-dns` of saved Ethernet/Wi-Fi/mobile profiles; originals stored in `/var/lib/cloudflare-switch/nm/` and restored by `off`; VPN profiles are never touched |
| `resolved` | systemd-resolved without NetworkManager (Arch, Omarchy, networkd servers) | one drop-in: `/etc/systemd/resolved.conf.d/90-cloudflare-switch.conf` |
| `resolvconf` | neither (Alpine, Void, minimal installs) | `/etc/resolv.conf`, original saved; refuses if it is a symlink managed by something else |

Force one with `--backend nm|resolved|resolvconf`.

### Why v2 replaced v1

The first version edited systemd-networkd `.network` files and restarted `systemd-networkd`. On a NetworkManager system (Fedora, Ubuntu) that fails on the missing `networkctl`, and *restarting* a stopped `systemd-networkd` would start it next to NetworkManager. v2 is **declarative**:

- `off` removes only what `on` added — it never edits files it doesn't own;
- **safety net:** if name resolution worked before `on` and stops afterwards, the change is rolled back automatically;
- no boot service is needed (drop-ins and NetworkManager profiles persist); a leftover v1 `cloudflare-switch-restore.service` is removed on the next `on`/`off`;
- `doctor` lists DNS settings it doesn't own, v1 leftovers, and NetworkManager profiles created after `on` (fix: `sync`).

It never touches `/etc/hosts`.

---

## Tests

```bash
bash tests/test_social_switch.sh        # as a normal user
bash tests/test_cloudflare_switch.sh    # as a normal user; fake nmcli / systemctl / resolvectl
```

Both honour a test-root hook (`SOCIAL_SWITCH_TEST_ROOT`, `CLOUDFLARE_SWITCH_TEST_ROOT`) that redirects every path into a temp directory. **The hook is ignored when running as root**, so an environment variable can never redirect a privileged run.

## Security notes

- The polkit action authorises one absolute path; argument validation lives in the scripts (platform table, hostname regex, option-looking input rejected).
- Run with `sudo`/`pkexec`, the environment is scrubbed, which is what makes the test hook safe.
- The desktop front ends only execute the CLI from `/usr/local/bin` or `/usr/bin` (root-owned).
- Browsers with Secure DNS / DoH bypass both `/etc/hosts` and system DNS. `doctor` reminds you.
