# Troubleshooting

Start with:

```sh
rez doctor          # checks the rules below and every module's health
rez status          # what's running, MemAvailable, disk
rez logs MODULE     # follow a module's log (rez logs alone = rez's own log)
```

Logs live in `~/.local/state/resurrect/logs/`. The boot log is `boot.log`.

## Services die at random (Android 12+)

Android 12 added a "phantom process killer" that kills background child processes of apps, which is exactly what Termux servers are. `rez doctor` detects it. Fix it once, from a computer with adb (USB debugging on):

```sh
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
adb shell settings put global settings_enable_monitor_phantom_procs false
```

On Android 14 and newer you can instead enable Developer options > "Disable child process restrictions". These settings can reset after a system update; `rez doctor` tells you.

## Nothing starts after a reboot

- Termux:Boot must be installed **from the same source as Termux** (F-Droid with F-Droid, GitHub with GitHub) and **opened once** after installing.
- Battery optimization: Settings > Apps > Termux (and Termux:Boot) > Battery > Unrestricted. Some vendors (Xiaomi, Huawei, Samsung, OnePlus...) have extra "auto-start" or "sleeping apps" settings; see https://dontkillmyapp.com
- Check `~/.local/state/resurrect/logs/boot.log`. Every boot writes `boot: start` and `boot: done`.

## Services start twice / "N copies running"

Termux:Boot runs **every** file in `~/.termux/boot/`. A backup copy of a startup script next to the real one means two startup scripts. resurrect writes exactly one file there (`resurrect`) and offers to move anything else to `~/.termux/boot-disabled/`. `rez doctor` fails if something else is there. Keep backups of startup scripts anywhere but in that folder.

The boot script also holds a lock, so a second copy exits immediately, and every service is started only if it isn't already running.

## "Already running" but it isn't (or the other way round)

resurrect never trusts a pidfile alone: after a reboot, Android hands old PIDs to unrelated processes. Every check reads `/proc/<pid>/cmdline`. If you write your own scripts, don't use `pgrep -f NAME` over ssh either: it matches the ssh command line that contains NAME. Use a bracket pattern (`pgrep -f '[n]tfy serve'`), or `rez status`.

## Low memory

Use MemAvailable, not `free`. Android's `free` counts page cache as used and looks nearly full on a healthy phone. `rez status` shows MemAvailable. If it stays below ~300 MB:

- Stop what you don't use: `rez stop jellyfin`, or set `MODULE.autostart=no`.
- Smaller AdGuard blocklists.
- `rez uninstall MODULE`.

## HTTPS / certificate errors

- **"certificate signed by unknown authority"** from a Go program (AdGuard upstreams, ntfy): it needs `SSL_CERT_FILE=$PREFIX/etc/tls/cert.pem` (Termux's CA bundle; `pkg install ca-certificates`). resurrect sets this for its services; add it if you run your own.
- **`ERR_SSL_PROTOCOL_ERROR` opening `http://something.ts.net`**: Chrome forces HTTPS for `.ts.net`. Open plain-HTTP pages by IP: `rez tailscale ip`.
- **Vaultwarden cert won't issue**: enable HTTPS certificates in the Tailscale admin console (DNS page), then `rez vaultwarden renew-cert`.

## Scripts fail with "No such file or directory" at boot

At boot, `termux-exec` isn't loaded, so `#!/usr/bin/env node` (or python) scripts can't start. resurrect's boot script and cron lines use full paths (`$PREFIX/bin/bash ...`). Do the same in your own boot-time scripts.

## No alerts arrive

- `rez ntfy test`
- Phone app: add the server URL from `rez status` / setup's summary, user `phone`, password from `rez ntfy show-phone-password`, subscribe to your topic (default `alerts`).
- The phone running the ntfy app must be on your tailnet (or the server must be reachable some other way).

## DNS problems

See [dns-and-adguard.md](dns-and-adguard.md#emergency-names-stop-resolving).

## Package installs fail

- Termux from Google Play is outdated; reinstall from F-Droid or GitHub.
- `termux-change-repo` to pick another mirror, then `pkg update`.

## Reporting a bug

`rez device --report` prints device details that are safe to paste into an issue (no serial numbers or addresses). Include `rez doctor` output and the relevant log lines, and **check them for passwords, tokens and addresses before posting**.
