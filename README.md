# resurrect

**Raise your dead phone as a homelab.**

resurrect turns an old Android phone or tablet into a small, private, self-hosted server using [Termux](https://termux.dev). Passwords, ad blocking, file sharing, sync, notifications, backups and smart alerts, reachable from anywhere over Tailscale, with nothing exposed to the internet.

- **No root needed.** Root is optional and only unlocks two extras.
- **Nothing is flashed, unlocked or rebooted for you.** Custom ROMs and rooting are explained, with links to official guides, never automated.
- **Built for phones.** One startup script with a lock, "is it running" checks that read `/proc`, not stale pidfiles, a health monitor with alerts, memory checks that use MemAvailable, and DNS that never takes your other devices down.

> Status: early (0.1). Built from a setup that ran on a real tablet; see [docs/testing.md](docs/testing.md) for exactly what has been tested where.

## Requirements

| | Minimum | Comfortable |
|---|---|---|
| Android | 7.0 (Termux's minimum) | 10+ |
| CPU | 64-bit ARM (arm64). 32-bit ARM works with fewer modules; x86_64 works | arm64 |
| RAM | 2 GB (Lite profile) | 3-4 GB (Standard), 6 GB+ (Full) |
| Free storage | 2 GB | 8 GB+, SD card for media |
| Apps | [Termux](https://f-droid.org/packages/com.termux/) and [Termux:Boot](https://f-droid.org/packages/com.termux.boot/), **from F-Droid or GitHub, not Google Play** | + [Termux:API](https://f-droid.org/packages/com.termux.api/) for battery readings |
| Power | Plugged in | With root: ACC charge limit to protect the battery |

A free [Tailscale](https://tailscale.com) account is needed for remote access (the default).

## Quick start

On the phone, in Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/JathinYanna04/resurrect/main/install.sh | bash
```

That checks you're in Termux, updates packages, downloads resurrect to `~/.resurrect` and starts `rez setup`, which asks before installing anything.

**Prefer to read it first?** (Recommended.)

```sh
pkg install -y git
git clone https://github.com/JathinYanna04/resurrect ~/.resurrect
less ~/.resurrect/install.sh
~/.resurrect/install.sh
```

**Non-interactive** (answers from flags or a file, see [config/resurrect.conf.example](config/resurrect.conf.example)):

```sh
~/.resurrect/install.sh --profile lite --modules vaultwarden,ntfy --yes
~/.resurrect/install.sh --config my-answers.conf --yes
rez --dry-run setup --profile standard          # show the plan and every command, change nothing
```

`--modules` installs exactly those modules plus their dependencies; `--profile` alone installs the profile's set.

After setup:

1. Open **Termux:Boot** once (Android only lets it start at boot after that).
2. Set Termux to **Unrestricted** battery use (Settings > Apps > Termux > Battery).
3. On Android 12+, turn off the phantom process killer: `rez doctor` shows how.
4. Reboot, then `rez status`: everything should come back by itself.

## What setup does

1. **Detects** Android version, CPU architecture, RAM (MemTotal and MemAvailable), free storage, SD card, root (only checked after asking), Termux source, Termux:Boot, and the Android 12+ phantom process killer.
2. **Recommends a profile** from the RAM.
3. **Lets you pick modules** (checkboxes). Modules that don't fit the device are shown with the reason and can't be selected.
4. **Asks each module's questions** (ports, HTTPS mode, folders...).
5. **Shows the plan:** modules, estimated RAM and disk, ports, startup. Then it asks before installing.
6. **Installs** in dependency order. Every step is idempotent: if something fails, fix it and run the same command again.
7. **Writes one boot script**, installs the scheduled jobs, runs `rez doctor` and prints how to reach everything.

## Profiles

| Profile | For | Modules | RAM in use |
|---|---|---|---|
| **Lite** | < 3 GB RAM | base, tailscale, ntfy, vaultwarden, backup, monitor | ~150 MB |
| **Standard** | 3-5 GB | Lite + adguard, copyparty, syncthing, alerts | ~350 MB |
| **Full** | 6 GB+ and an SD card | Standard + jellyfin | ~700 MB with Jellyfin running |

Phones report less RAM than advertised (a "3 GB" phone shows about 2.8 GB), and the thresholds account for that. You can always add or remove modules.

## Modules

Each is optional (except base), and each has install / start / stop / status / uninstall.

| Module | What | Port |
|---|---|---|
| **base** | Termux packages, SSH (keys only), wake lock, cron, the boot script | 8022 |
| **tailscale** | Private remote access. Built-in (userspace, in Debian) or the Android app | - |
| **cloudflared** | Optional Cloudflare Tunnel for services you deliberately make **public** | - |
| **ntfy** | Push notifications; every alert goes here. Local server or an existing one | 2586 |
| **vaultwarden** | Bitwarden-compatible password manager, HTTPS (Tailscale certificate), sign-ups closed automatically after your account exists | 8222 |
| **adguard** | AdGuard Home ad blocking. Port 53 with root, 5335 without. [Read the DNS safety notes](docs/dns-and-adguard.md) | 53/5335, UI 3000 |
| **copyparty** | File sharing in the browser, WebDAV, uploads | 3923 |
| **filebrowser** | Alternative web file manager | 8085 |
| **syncthing** | Folder sync with your other devices | 8384 |
| **backup** | Nightly archive of every module's data, keep N, weekly restore test, alerts if nothing was copied off the phone | - |
| **monitor** | Checks every module and the phone (disk, memory, battery temperature) every minute; alerts after 2 failures, restarts the service, tells you when it recovers | - |
| **alerts** | Smart alerts: an LLM (your key, any OpenAI-compatible endpoint) filters feeds, APIs and web pages for what you described; hits arrive in ntfy | - |
| **jellyfin** | Media server, direct play only. Offered only with enough RAM and an SD card | 8096 |
| **acc** | Root only: battery charge limit (stop at 80 %, resume at 70 %) | - |

`rez modules` shows which ones fit your device.

### Smart alerts

Describe what you care about in plain words; resurrect fetches new items on a schedule, asks your LLM to score them, and sends the good ones:

```toml
name = "job-postings"
schedule = "0 */6 * * *"
[[sources]]
type = "rss"
url = "https://weworkremotely.com/categories/remote-programming-jobs.rss"
[llm]
base_url = "https://api.openai.com/v1"     # or OpenRouter, Groq, a local llama.cpp/Ollama server...
model = "gpt-4o-mini"
min_score = 7
prompt = "Junior backend roles (Python/Go), remote or hybrid. Not senior-only, not sales."
```

Examples in [alerts/examples/](alerts/examples/): job postings, research papers (arXiv), and a price-drop watcher. Copy them to `~/.config/resurrect/alerts/`, set `enabled = true`, then `rez alerts sync`. Test without sending: `rez alerts run job-postings --dry-run`. Items are de-duplicated, so you never pay twice for the same item, and the first run only learns what already exists.

## Root vs no root

| | Without root | With root |
|---|---|---|
| Everything in the module list except acc | yes | yes |
| AdGuard Home DNS port | 5335 (computers use a small forwarder) | 53 (any device), started by Magisk at boot |
| Battery charge limit | no | ACC |
| Setup | automatic | root itself is a manual, guided process: [docs/rooting.md](docs/rooting.md) |

## Commands

```sh
rez status                     # what's running, memory, disk
rez doctor                     # check everything, explain problems
rez start|stop|restart [module]
rez logs [module]
rez install|uninstall module
rez backup run|list|verify|extract
rez alerts list|run|test|sync
rez device [--report]          # hardware, ROM, custom ROM options (read-only)
rez ntfy test                  # send a test notification
rez vaultwarden show-admin-password
rez help
```

## How it stays up

These come from a phone that ran a homelab for months, and from the outages along the way:

- **One startup script.** Termux:Boot runs *every* file in `~/.termux/boot/`. resurrect writes exactly one, holds a lock so a second copy exits, and moves other files aside if you agree. (A backup copy of a boot script once started a database twice, and it shut itself down.)
- **No trusted pidfiles.** After a reboot Android reuses PIDs, so "is the old PID alive?" lies. Every check compares `/proc/<pid>/cmdline`. (A stale pidfile once kept AdGuard down after a reboot, and with it DNS for every device.)
- **No self-matching.** `pgrep -f name` over ssh matches your own ssh command. resurrect matches exact argv entries and skips itself.
- **Start only if not running**, everywhere; `rez status` flags duplicates.
- **MemAvailable, not `free`.** Android's `free` makes a healthy phone look full.
- **The phone is never anyone's only DNS server.** See [docs/dns-and-adguard.md](docs/dns-and-adguard.md).
- **Supervised daemons** restart with backoff and send an alert.
- **Backups leave the phone**, and the phone complains if they don't.

## Documentation

- [Troubleshooting](docs/troubleshooting.md)
- [DNS and AdGuard: safety, fallback, emergency steps](docs/dns-and-adguard.md)
- [Remote access: Tailscale and Cloudflare Tunnel](docs/remote-access.md)
- [Security notes](docs/security.md)
- [Backups and restore](docs/backups.md)
- [Computer-side extras: backup pulls, DNS fallback](extras/laptop/README.md)
- [Custom ROMs (optional, manual)](docs/custom-rom.md)
- [Rooting (optional, manual)](docs/rooting.md)
- [Writing a module](docs/writing-a-module.md)
- [Testing: what is tested where](docs/testing.md)

## Troubleshooting

The three most common problems:

- **Services die at random on Android 12+**: the phantom process killer. `rez doctor` prints the one-time fix.
- **Nothing starts after a reboot**: Termux:Boot not opened once, or battery optimization. [Details](docs/troubleshooting.md#nothing-starts-after-a-reboot).
- **A `.ts.net` page won't open in Chrome**: Chrome forces HTTPS for `.ts.net`; open plain-HTTP pages by Tailscale IP (`rez tailscale ip`).

More: [docs/troubleshooting.md](docs/troubleshooting.md).

## FAQ

**Is a phone really good enough?** For a household's passwords, notifications, ad blocking and files, yes. A phone from the last ten years has more CPU than most single-board computers, plus a built-in battery as a UPS. Heavy media transcoding is where it falls short (Jellyfin is direct-play only).

**Does it need to stay plugged in?** Yes. With root, ACC keeps the battery between 70 and 80 %, which is much kinder than sitting at 100 %. Without root, keep an eye on battery swelling, and consider a smart plug on a schedule.

**Why Tailscale instead of opening ports?** Your services stay invisible to the internet, it works on mobile networks and behind carrier NAT, and there's no router to configure. Cloudflare Tunnel exists for the few things you might want public.

**Why proot Debian for some services?** Some programs expect a normal Linux filesystem (`/etc/resolv.conf`, `/etc/ssl`, `/var/lib`). Debian in proot provides that without root. Everything that runs natively in Termux does.

**Will it work on my phone?** If Termux runs, the base works. Run `rez device --report` and open a device report issue: it helps others.

**Can I use my own LLM for smart alerts?** Yes: any OpenAI-compatible endpoint, including a local llama.cpp or Ollama server on another machine.

**How do I update?** `git -C ~/.resurrect pull`, then `rez install <module>` for modules whose pinned version changed (see the changelog). `pkg upgrade` updates Termux packages.

**How do I remove everything?** `rez uninstall <module> --purge` for each module, then delete `~/.resurrect`, `~/.config/resurrect`, `~/.local/share/resurrect`, `~/.local/state/resurrect` and `~/.termux/boot/resurrect`.

## Disclaimer

resurrect is provided as-is, without warranty (see [LICENSE](LICENSE)). You are responsible for your device, your data and what you expose to the network. Running a phone permanently plugged in carries a small risk of battery swelling; check it now and then. Unlocking bootloaders, rooting and installing custom ROMs can erase data, void warranties and brick devices; resurrect never does any of it for you and only links to official guides. Not affiliated with Termux, Tailscale, Bitwarden, Vaultwarden, AdGuard, Cloudflare, Jellyfin or any other project mentioned.

## Contributing

Device reports, bug reports and modules are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
