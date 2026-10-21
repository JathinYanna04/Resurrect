# shellcheck shell=bash
# cloudflared: optional Cloudflare Tunnel for services you WANT public.
#
# Tailscale keeps everything private; a tunnel puts a service on the public
# internet. Only publish what is built for that, put Cloudflare Access in
# front of it, and never publish admin pages (Vaultwarden /admin, AdGuard,
# Syncthing GUI). See docs/remote-access.md.

MOD_NAME=cloudflared
MOD_DESC="Cloudflare Tunnel (optional, makes chosen services PUBLIC)"
MOD_DEPENDS="base"
MOD_RAM_EST_MB=30
MOD_DISK_EST_MB=40
MOD_TESTED="no (needs a Cloudflare account)"

mod_configure() {
  if ! secret_get cloudflared_token >/dev/null; then
    local f t=''
    f=$(cfg_get cloudflared.token_file "")
    if [[ -n "$f" ]]; then t=$(head -n1 "${f/#\~/$HOME}"); cfg_unset cloudflared.token_file
    elif [[ $(ui_mode) != none ]]; then
      ui_msg "Cloudflare Tunnel" "This makes services reachable from the PUBLIC internet.
1. In the Cloudflare dashboard: Zero Trust > Networks > Tunnels > Create a tunnel (cloudflared).
2. Copy the tunnel token (the long string after --token).
3. Add public hostnames there, pointing to http://localhost:PORT.
4. Protect them with Cloudflare Access. Never publish admin pages."
      t=$(ui_password "Cloudflare Tunnel" "Tunnel token")
    fi
    [[ -n "$t" ]] || die "cloudflared needs a tunnel token (cloudflared.token_file in --config)"
    secret_set cloudflared_token "$t"
  fi
}

mod_install() { is_termux && run pkg install -y cloudflared; return 0; }

mod_start() {
  local t
  t=$(secret_get cloudflared_token) || die "no tunnel token: rez install cloudflared"
  # Token via the environment, not argv: argv is visible in /proc.
  SVC_ENV=("TUNNEL_TOKEN=$t")
  SVC_SUPERVISE=1 svc_start cloudflared cloudflared "tunnel" -- cloudflared tunnel --no-autoupdate run
}

mod_stop() { svc_stop cloudflared cloudflared "tunnel"; }
mod_status() { svc_status_line cloudflared cloudflared "tunnel" "routes are configured in the Cloudflare dashboard"; }
mod_health() { svc_running cloudflared cloudflared "tunnel"; }

mod_uninstall() {
  secret_del cloudflared_token
  info "delete the tunnel in the Cloudflare dashboard too"
}

mod_info() { echo "Tunnel:     public hostnames are listed in the Cloudflare Zero Trust dashboard"; }
