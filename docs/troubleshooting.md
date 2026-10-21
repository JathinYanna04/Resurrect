# Troubleshooting

This guide is organized by symptom. Each entry explains the likely cause and the fix. Start with the diagnostic commands below; they point at most problems directly. If nothing here helps, the last section explains how to report a bug.

## Contents

- [First steps](#first-steps)
- [Services don't start after a reboot](#services-dont-start-after-a-reboot)
- [Termux gets killed in the background](#termux-gets-killed-in-the-background)
- [DNS stopped working](#dns-stopped-working)
- [A service runs twice](#a-service-runs-twice)
- [A service shows "running" but isn't, or the other way round](#a-service-shows-running-but-isnt-or-the-other-way-round)
- [A module fails to install](#a-module-fails-to-install)
- [The device is low on memory](#the-device-is-low-on-memory)
- [Certificate and HTTPS errors](#certificate-and-https-errors)
- [Alerts don't arrive](#alerts-dont-arrive)
- [Can't connect over SSH](#cant-connect-over-ssh)
- [Scripts fail at boot with "No such file or directory"](#scripts-fail-at-boot-with-no-such-file-or-directory)
- [Reporting a bug](#reporting-a-bug)

## First steps

```bash
rez doctor          # checks the reliability rules and every module's health
rez status          # what's running, MemAvailable, free storage
rez logs <module>   # follow one module's log; rez logs alone shows rez's own log
```

`rez doctor` ends with a summary such as `no problems, 1 warning(s)` or `2 problem(s), 1 warning(s)`. Every `FAIL` line says what to do next. One warning always appears, because battery optimization can't be checked from inside Termux.

All logs are in `~/.local/state/resurrect/logs/`. The boot log is `boot.log`.

## Services don't start after a reboot

**Cause 1: Termux:Boot was never opened, or comes from a different source than Termux.** Android only lets Termux:Boot run at boot after it has been opened once, and it only works with a Termux from the same source.

**Fix:** install Termux:Boot from the same place as Termux (F-Droid with F-Droid, GitHub with GitHub) and open it once. `rez doctor` reports `Termux:Boot not installed` if it is missing.

**Cause 2: battery optimization.** Android stops apps it considers idle.

**Fix:** set Settings > Apps > Termux > Battery to **Unrestricted**, and do the same for Termux:Boot. Some vendors add their own "auto-start" or "sleeping apps" settings; [dontkillmyapp.com](https://dontkillmyapp.com) lists them by manufacturer.

**Cause 3: the module has autostart turned off.** `rez boot` skips modules with `<module>.autostart=no` in `~/.config/resurrect/resurrect.conf`. Jellyfin is installed this way unless you chose otherwise.

**Fix:** start it by hand with `rez start <module>`, or remove the `autostart=no` line.

**How to check:** every boot writes two lines to `boot.log`.

```bash
tail ~/.local/state/resurrect/logs/boot.log
```

```text
2026-01-01 08:00:12 boot: start
2026-01-01 08:00:31 boot: done (rc 0)
```

If no new lines appear after a reboot, Termux:Boot didn't run the script. If `boot: done` shows a non-zero code, a module failed to start; `rez status` shows which.

## Termux gets killed in the background

**Symptom:** services die at random, often minutes or hours after starting, on Android 12 or newer.

**Cause:** Android 12 added a "phantom process killer" that stops background child processes of apps, which is exactly what Termux services are. `rez doctor` detects it.

**Fix:** turn it off once, from a computer with [adb](https://developer.android.com/tools/releases/platform-tools) and USB debugging enabled:

```bash
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
adb shell settings put global settings_enable_monitor_phantom_procs false
```

On Android 14 and newer you can instead enable **Developer options > Disable child process restrictions**.

These settings can be reset by a system update. Run `rez doctor` after updates; it reports `phantom process killer disabled` when the fix is in place.

Also check battery optimization, as described in [the previous section](#services-dont-start-after-a-reboot).

## DNS stopped working

**Symptom:** web pages and apps on your other devices stop loading, while IP addresses still work.

**Cause:** a device depends on AdGuard Home on your resurrect device, and AdGuard Home is down or unreachable.

**Fix:** follow the emergency steps in [dns-and-adguard.md](dns-and-adguard.md#emergency-names-stop-resolving). In short: turn off Tailscale-wide DNS in the admin console, run `tailscale set --accept-dns=false` on affected devices, then check AdGuard Home with `rez adguard test`.

To prevent it from happening again, give every client a fallback resolver, as described in [dns-and-adguard.md](dns-and-adguard.md#point-clients-at-it-safely).

## A service runs twice

**Symptom:** `rez status` shows `N copies running!` next to a module.

**Cause:** Termux:Boot runs **every** file in `~/.termux/boot/`. A second startup script, such as a backup copy of an old one, starts services a second time.

**Fix:** resurrect writes exactly one file there, `resurrect`. During setup it offers to move anything else to `~/.termux/boot-disabled/`, and `rez doctor` fails while other files are present. Move them out by hand:

```bash
mkdir -p ~/.termux/boot-disabled
mv ~/.termux/boot/<other file> ~/.termux/boot-disabled/
rez restart <module>
```

`rez stop` and `rez restart` stop every running copy, so the restart leaves exactly one.

Keep copies of startup scripts anywhere except `~/.termux/boot/`. The boot script also holds a lock, so a second copy of resurrect's own script exits immediately.

## A service shows "running" but isn't, or the other way round

**Cause:** your own scripts trust a pidfile or `pgrep`. After a reboot, Android hands old PIDs to unrelated processes, so "is that PID alive?" gives the wrong answer. `pgrep -f NAME` run over SSH also matches the SSH command line that contains NAME.

**Fix:** use `rez status`, which reads `/proc/<pid>/cmdline` and ignores stale pidfiles. In your own scripts, use a bracket pattern such as `pgrep -f '[n]tfy serve'` so the pattern doesn't match itself.

## A module fails to install

**Symptom:** `<module> failed to install. Fix the problem above and run the same command again`.

**Cause:** usually a download or package problem. The error above that line names it.

**Fix:**

- `checksum mismatch`: the download was corrupted or changed upstream. Run the same command again. If it keeps failing, [open an issue](https://github.com/JathinYanna04/Resurrect/issues/new?template=bug.yml); never edit the checksum yourself.
- Package installs fail: Termux from Google Play is outdated, so reinstall Termux from F-Droid or GitHub. Otherwise pick another mirror with `termux-change-repo` and run `pkg update`.
- `<module> cannot be installed here: needs root` (or RAM, storage, architecture): the module doesn't fit this device. `rez modules` shows the reason for each module.

Every install step is idempotent, so running `rez install <module>` again skips what already finished.

## The device is low on memory

**Cause:** too many modules for the device, or large AdGuard Home blocklists.

**Fix:** check MemAvailable, not `free`. Android's `free` counts the page cache as used and makes a healthy device look full. `rez status` shows MemAvailable, and `rez doctor` fails below 300 MB. To free memory:

- Stop what you don't use: `rez stop jellyfin`, and set `jellyfin.autostart=no` in the config file.
- Use smaller AdGuard Home blocklists.
- Remove modules: `rez uninstall <module>`.

## Certificate and HTTPS errors

| Error | Cause | Fix |
|---|---|---|
| `certificate signed by unknown authority` from a Go program | It can't find CA certificates on Android | resurrect sets `SSL_CERT_FILE=$PREFIX/etc/tls/cert.pem` for its services. Set it for programs you run yourself |
| `ERR_SSL_PROTOCOL_ERROR` opening `http://<name>.ts.net` | Browsers force HTTPS for `.ts.net` | Open plain-HTTP services by IP: `rez tailscale ip` |
| `tailscale cert failed` | HTTPS certificates are off for your tailnet | Enable them in the Tailscale admin console (DNS page), then `rez vaultwarden renew-cert` |
| A Bitwarden app refuses the server | Self-signed certificate not trusted | See [security.md](security.md#hardening-checklist) |

## Alerts don't arrive

1. Send a test:

   ```bash
   rez ntfy test
   ```

   Expected output: ` ok sent (check your phone)`. The command reports success even when delivery fails, because alerts never stop the command that sends them; undelivered alerts are logged as `NOTIFY FAILED` in `~/.local/state/resurrect/logs/rez.log`.
2. In the ntfy app on your phone, add the server address that setup printed, log in as `phone` with the password from `rez ntfy show-phone-password`, and subscribe to your topic (default `alerts`).
3. The phone with the ntfy app must be able to reach the server, so it needs to be on your tailnet when the server runs on the resurrect device.

## Can't connect over SSH

**Cause 1: no key was added.** sshd only starts once `~/.ssh/authorized_keys` contains a key. `rez status` shows `NO KEY` next to sshd.

**Fix:**

```bash
rez base add-key 'ssh-ed25519 AAAA... you@computer'
rez start base
```

**Cause 2: wrong port or user.** Termux's sshd listens on port 8022, and the user is Termux's app user. Run `whoami` in Termux to see it.

```bash
ssh -p 8022 <termux user>@<device address>
```

Password login is turned off on purpose.

## Scripts fail at boot with "No such file or directory"

**Cause:** at boot, `termux-exec` isn't loaded, so scripts that start with `#!/usr/bin/env python3` (or `node`, `bash`) can't run.

**Fix:** use full paths, as resurrect's boot script and cron lines do: `$PREFIX/bin/bash script.sh` or `$PREFIX/bin/python3 script.py`.

## Reporting a bug

1. Collect device details. This output contains no serial numbers or network addresses:

   ```bash
   rez device --report
   ```

2. Add the output of `rez doctor` and the relevant log lines.
3. **Remove passwords, tokens and addresses** from logs before posting.
4. Open a [bug report](https://github.com/JathinYanna04/Resurrect/issues/new?template=bug.yml).
