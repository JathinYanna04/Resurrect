# Security notes

A phone running your passwords and files deserves the same care as a server. What resurrect does by default, and what's left to you.

## Defaults

| Area | Default |
|---|---|
| Remote access | Tailscale only. Nothing is port-forwarded or published unless you add Cloudflare Tunnel |
| SSH | Key login only; password login is turned off (`PasswordAuthentication no`) |
| Service binding | With built-in Tailscale: services listen on `127.0.0.1`, so they're reachable over Tailscale but not from the Wi-Fi network. With the Tailscale app: all interfaces, so every service has a password |
| ntfy | `deny-all`: resurrect gets a publish-only token, your phone a read-only user, you the admin |
| Vaultwarden | HTTPS; sign-ups close automatically once the first account exists, and a test registration must be refused; admin token stored as an argon2id hash |
| AdGuard, copyparty, File Browser, Syncthing | Admin login required; generated passwords |
| Secrets | One file each in `~/.config/resurrect/secrets/` (mode 600, folder 700). Never in the config file, never in logs, never on command lines (tokens are passed through the environment or files) |
| Downloads | Pinned versions with SHA-256 checksums (Vaultwarden: image digest; copyparty: pip `--require-hashes`). A mismatch aborts |
| Backups | Mode 700; they contain secrets, so treat copies the same way |
| Config file | Parsed, never executed (`$(...)` in it does nothing) |

## Things to know

**Tailscale userspace mode exposes localhost.** Built-in Tailscale runs in userspace networking mode and hands incoming tailnet connections to `127.0.0.1`. That's what makes `127.0.0.1` binding work, but it also means **every service listening on localhost on the phone is reachable by every device in your tailnet**, including things you started yourself (a database, a debug server). If you share your tailnet with other people, restrict access with Tailscale ACLs: https://tailscale.com/kb/1018/acls

**Termux apps share one user.** Every process in Termux runs as the same Android user, so a compromised service could read the others' data and the secrets folder. Don't install untrusted code in the same Termux. Android's app sandbox still separates Termux from your other apps.

**The phone is physically exposed.** Use a screen lock. Android's file-based encryption protects data at rest only while the phone is locked after a restart. Anyone with physical access to an unlocked, rooted phone has everything.

**Cloudflare Tunnel makes things public.** Only publish what is built for the internet, put Cloudflare Access in front, and never publish admin pages: Vaultwarden `/admin`, AdGuard, the Syncthing GUI. See [remote-access.md](remote-access.md).

**Self-signed Vaultwarden certificate.** If you chose self-signed instead of the Tailscale certificate, Bitwarden apps only connect after you install the certificate as trusted on each device. The file is `~/.local/share/resurrect/vaultwarden/tls/cert.pem`. Prefer the Tailscale certificate (enable HTTPS in the Tailscale admin console, DNS page).

**Turn on two-step login in Vaultwarden** (web vault > Settings > Security > Two-step login). resurrect can't do that for you.

**Updates.** `pkg upgrade` updates Termux packages. Pinned binaries (Tailscale, ntfy, Vaultwarden, AdGuard, File Browser) update when resurrect bumps its pins: `git -C ~/.resurrect pull`, then `rez install <module>` again. Watch the upstream security advisories for Vaultwarden in particular.

**Root.** Root lets a compromised app do far more. Grant Termux root only if you use the root-only modules, and never grant it to apps you don't need. See [rooting.md](rooting.md).

## Showing generated passwords

```sh
rez vaultwarden show-admin-password
rez ntfy show-phone-password
rez copyparty show-password      # also: filebrowser, syncthing
```

Store them in Vaultwarden, then change them in each service's UI if you like.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Use GitHub's private vulnerability reporting on the repository (Security tab > Report a vulnerability).
