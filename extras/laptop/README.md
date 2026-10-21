# Computer-side extras

Small scripts for the computer you manage the phone from. Nothing here runs on the phone.

## Pull backups off the phone

A backup that only lives on the phone dies with the phone. `pull-backups.sh` copies the nightly archives to your computer over SSH:

```sh
./pull-backups.sh PHONE [DEST]
```

- `PHONE` is an SSH destination. The easiest is an alias in `~/.ssh/config`:

  ```
  Host phone
      HostName <phone's Tailscale name or IP>
      Port 8022
      User <the Termux user: run whoami in Termux>
      IdentityFile ~/.ssh/id_ed25519
  ```

- `DEST` defaults to `~/resurrect-backups/PHONE`.
- It never uses `--delete`: if the phone is wiped, your copies stay. It prunes old copies itself, keeping the newest 14 (`REZ_KEEP`).
- Every archive is checked against the checksum the phone wrote. A mismatch fails the run.
- If the phone can't be reached (you're away, it's rebooting), it logs that and exits successfully.
- After a good pull it runs `rez backup mark-pulled` on the phone. With `backup.expect_pull=yes`, the phone alerts you when no pull has happened for 3 days.

### Run it daily

**Linux (systemd user timer):**

```sh
install -Dm755 pull-backups.sh ~/.local/bin/resurrect-pull-backups
install -Dm644 systemd/resurrect-pull-backups@.service systemd/resurrect-pull-backups@.timer -t ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now resurrect-pull-backups@phone.timer   # "phone" = your ssh alias
journalctl --user -u resurrect-pull-backups@phone                  # logs
```

`Persistent=true` means a run missed while the computer was off happens at the next start.

**macOS or anything with cron:**

```
0 9 * * * /path/to/pull-backups.sh phone >> ~/resurrect-pull.log 2>&1
```

## Use the phone's AdGuard without risking your internet

**Never make the phone the only DNS server for your devices.** If it reboots, crashes, runs out of battery or drops off Wi-Fi, every device that depends on it loses the internet. Most operating systems don't fall back reliably when you list a second DNS server: some query both at once (and leak around the blocker), some stick with the dead one for a while.

The setup in `dns-fallback/` runs a tiny local forwarder ([dnsproxy](https://github.com/AdguardTeam/dnsproxy)) on the computer. Every lookup tries the phone first and falls back to a public resolver within 2 seconds:

```
apps -> systemd-resolved -> dnsproxy (127.0.0.1:5353) -> phone AdGuard (TCP)
                                                       \-> fallback: Quad9 over TLS
```

DNS to the phone uses TCP on purpose: userspace Tailscale on Android has crashed on inbound UDP forwarding.

**Linux with systemd-resolved:**

```sh
sudo bash dns-fallback/setup-linux.sh --phone <phone address> --port 5335   # 53 if AdGuard runs in root mode
# optional: --networkmanager (stop per-Wi-Fi DNS racing AdGuard), --tailscale (stop Tailscale overriding DNS)
sudo bash dns-fallback/undo-linux.sh                                        # remove everything
```

Check that it works, then prove the fallback:

```sh
resolvectl query example.com
# on the phone: rez stop adguard
resolvectl query example.com     # must still resolve (via the fallback)
# on the phone: rez start adguard
```

**macOS and Windows:** install dnsproxy (Homebrew: `brew install dnsproxy`, or a release binary), and run it with the same options as in `setup-linux.sh`:

```sh
dnsproxy -l 127.0.0.1 -p 53 -u tcp://<phone address>:5335 -u "[/ts.net/]100.100.100.100" \
  -f tls://dns.quad9.net -b 9.9.9.9:53 --timeout=2s --cache
```

Then set the system DNS server to `127.0.0.1`. To undo, set DNS back to automatic.

**Phones and other devices:** point them at the phone only if you accept that they lose DNS when it is down. Android's "Private DNS" and iOS DNS profiles have no fallback. For a whole network, use your router's DNS settings with the phone as primary *and* a public resolver as secondary, knowing that some ads will get through the secondary.

### If names stop resolving (emergency)

1. On the affected computer: `sudo bash dns-fallback/undo-linux.sh` (or set DNS back to automatic).
2. If you made the phone a **Tailscale global nameserver**: open the Tailscale admin console, DNS page, and turn off "Override local DNS" or remove the phone's address. If the device you're on has no DNS, use a phone on mobile data with Tailscale switched off.
3. On a single device right now: `tailscale set --accept-dns=false` (Android app: Settings > Use Tailscale DNS off).
4. Fix AdGuard on the phone (`rez status`, `rez logs adguard`, `rez adguard test`), then turn things back on.
