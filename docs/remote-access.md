# Remote access

## Tailscale (default)

Tailscale puts the phone on your private network ("tailnet") together with your laptop and other phone. Nothing is exposed to the internet, no router configuration, and it works across mobile data and NAT.

### Built-in mode (default)

`tailscaled` runs inside Debian (proot) in userspace-networking mode, started at boot like every other service.

- It doesn't use Android's single VPN slot, so you can still use another VPN app.
- `tailscale cert` works, which gives Vaultwarden a real HTTPS certificate.
- Incoming tailnet connections are handed to `127.0.0.1`, so services bound to localhost are reachable over Tailscale but not from Wi-Fi. That means **every localhost service is reachable by your tailnet peers** (see [security.md](security.md)).
- It runs under a supervisor that restarts it and sends an alert if it exits. Userspace tailscaled has crashed on inbound UDP forwarding; keep DNS traffic to the phone on TCP ([dns-and-adguard.md](dns-and-adguard.md)).

Commands:

```sh
rez tailscale up        # log in (prints a link); or put a one-time auth key in tailscale.authkey_file
rez tailscale status
rez tailscale ip
```

For HTTPS certificates, enable "HTTPS Certificates" in the Tailscale admin console (DNS page). The certificate name is `<device>.<your-tailnet>.ts.net`. resurrect renews it weekly.

**Browsers and `.ts.net`:** Chrome forces HTTPS for every `*.ts.net` name. Pages without TLS (AdGuard, ntfy, copyparty, Syncthing) fail to open by name with `ERR_SSL_PROTOCOL_ERROR`. Open them by the phone's Tailscale IP instead (`rez tailscale ip`): `http://100.x.y.z:3000`.

### App mode

The official Android app. It's simpler, but it can't issue certificates (no CLI), and it occupies the VPN slot. Services then listen on all interfaces, protected by their passwords. Choose it with `tailscale.mode=app` or in the setup menu.

## Cloudflare Tunnel (optional, public)

Use this only for services you want reachable **from the internet without Tailscale**, such as sharing a copyparty folder with a friend.

1. In the Cloudflare dashboard: Zero Trust > Networks > Tunnels > Create a tunnel (cloudflared). Copy the token.
2. `rez install cloudflared` and paste the token (stored as a secret, passed to cloudflared through the environment, never on the command line).
3. In the dashboard, add a public hostname pointing to `http://localhost:PORT`.
4. Protect it with Cloudflare Access (Zero Trust > Access > Applications). Without Access, anyone with the link can reach the service's login page.

**Never publish:** Vaultwarden's `/admin`, AdGuard Home, the Syncthing GUI, File Browser with admin rights, ntfy's admin user. Prefer Tailscale for anything personal.
