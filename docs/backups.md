# Backups and restore

## What runs

| When | What |
|---|---|
| Daily 03:30 | `rez backup run`: one archive `~/resurrect-backups/resurrect-DATE_TIME.tar.gz` plus its `.sha256`; keeps the newest `backup.keep` (default 7) |
| Sunday 05:15 | `rez backup verify`: restore test of the newest archive into a scratch folder |
| Your computer, daily | `extras/laptop/pull-backups.sh`: copies archives off the phone ([extras/laptop/README.md](../extras/laptop/README.md)) |

Failures send an ntfy alert. The monitor also alerts if no backup succeeded for 36 hours, and (with `backup.expect_pull=yes`) if no computer pulled a copy for 3 days.

## What's inside

Each module decides what matters and backs it up consistently while it runs:

| Module | Contents |
|---|---|
| base | `resurrect.conf`, `authorized_keys`, `sshd_config`, crontab |
| tailscale | node state (same identity and IP after restore, no new login) |
| ntfy | `server.yml`, user database (SQLite `.backup`) |
| vaultwarden | database (SQLite `.backup`), RSA keys, attachments, sends, `config.json`, admin token hash |
| adguard | `AdGuardHome.yaml` (filters and logs re-download / rebuild) |
| copyparty, filebrowser, syncthing | configuration and identities (not the shared files themselves) |
| alerts | job files and state database |
| jellyfin | library database and settings (not metadata images or media) |

Binaries are not backed up; they're re-downloaded and verified on reinstall. **Your shared files, synced folders and media are not in these archives**: back those up separately, or let Syncthing keep a copy on another device.

The archives contain secrets (password hashes, keys, Tailscale node state). Keep copies somewhere private.

## Restore test

```sh
rez backup verify                 # newest archive
rez backup verify FILE            # a specific one
```

This checks the checksum, extracts into a scratch folder and runs each module's check (for example SQLite `integrity_check` and the Vaultwarden user count). It touches nothing live.

## Restoring

The order is always: install the module, stop it, put the files back, start it.

```sh
rez backup extract ~/resurrect-backups/resurrect-2026-01-01_0330.tar.gz ~/restore
ls ~/restore        # one folder per module, plus MANIFEST
```

### On a fresh phone

1. Install Termux, Termux:Boot, then resurrect (README).
2. Copy the archive to the phone (for example `scp -P 8022 archive phone:`).
3. `rez backup extract archive ~/restore`
4. Copy your old settings first: `cp ~/restore/base/resurrect.conf ~/.config/resurrect/resurrect.conf`
5. `rez setup --yes --config ~/.config/resurrect/resurrect.conf` (reinstalls the same modules with the same answers)
6. Restore each module's data as below.

### Per module

```sh
# Vaultwarden
rez stop vaultwarden
cp ~/restore/vaultwarden/db.sqlite3 ~/restore/vaultwarden/rsa_key* ~/.local/share/resurrect/vaultwarden/data/
cp -r ~/restore/vaultwarden/attachments ~/restore/vaultwarden/sends ~/.local/share/resurrect/vaultwarden/data/ 2>/dev/null
cp ~/restore/vaultwarden/config.json ~/.local/share/resurrect/vaultwarden/data/ 2>/dev/null
rez start vaultwarden

# ntfy
rez stop ntfy
cp ~/restore/ntfy/user.db ~/.local/share/resurrect/ntfy/
rez start ntfy

# Tailscale (same node identity, no new login)
rez stop tailscale
cp ~/restore/tailscale/tailscaled.state "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/var/lib/tailscale/"
rez start tailscale
# (older proot-distro: .../installed-rootfs/debian/var/lib/tailscale/)

# AdGuard (no root)
rez stop adguard
cp ~/restore/adguard/AdGuardHome.yaml ~/.local/share/resurrect/adguard/
rez start adguard
# AdGuard (root): su -c 'cp ~/restore/adguard/AdGuardHome.yaml /data/adb/resurrect/adguard/'

# Smart alerts
cp ~/restore/alerts/jobs/*.toml ~/.config/resurrect/alerts/
rez alerts sync
```

Then `rez status` and `rez doctor`.
