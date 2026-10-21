# shellcheck shell=bash
# tailscale: private remote access. Nothing is exposed to the internet.
#
# Two modes:
#   proot (default) tailscaled in userspace-networking mode inside Debian.
#                   No VPN slot used, `tailscale cert` works (Vaultwarden
#                   HTTPS), runs at boot with the other services.
#   app             the official Android app. Simpler, but has no CLI, so no
#                   `tailscale cert`; resurrect only reminds you it exists.
#
# Lessons baked in:
#   * Userspace tailscaled forwards tailnet connections to 127.0.0.1, so every
#     service listening on localhost is reachable by your tailnet peers. Use
#     Tailscale ACLs if you share your tailnet (docs/security.md).
#   * Userspace tailscaled has crashed on inbound UDP forwarding. It runs under
#     the supervisor (restart + alert), and DNS to this device should use TCP
#     (docs/dns-and-adguard.md).
#   * The device itself never uses tailnet DNS (--accept-dns=false), so it can
#     never depend on a resolver that runs on itself.

MOD_NAME=tailscale
MOD_DESC="Tailscale private remote access (default, nothing public)"
MOD_DEPENDS="base"
MOD_RAM_EST_MB=40
MOD_DISK_EST_MB=250
MOD_TESTED="no (needs a real device and a tailnet)"

TS_DIR=/var/lib/tailscale
TS_SOCK=$TS_DIR/tailscaled.sock

_mode() { cfg_get tailscale.mode proot; }

ts() { proot_exec /usr/local/bin/tailscale --socket="$TS_SOCK" "$@"; }

mod_configure() {
  local mode
  mode=$(cfg_get tailscale.mode "")
  if [[ -z "$mode" ]]; then
    mode=$(ui_menu "Tailscale" "How should this phone join your tailnet?" proot \
      proot "Built in (recommended): runs with the other services, enables HTTPS certs" \
      app "Android Tailscale app: simpler, but no HTTPS certs for Vaultwarden")
  fi
  cfg_set tailscale.mode "$mode"
  if [[ "$mode" == proot ]]; then
    cfg_set tailscale.hostname "$(cfg_get tailscale.hostname "$(ui_input "Tailscale" "Device name on your tailnet" "resurrect")")"
    local kf
    kf=$(cfg_get tailscale.authkey_file "")
    if [[ -n "$kf" ]]; then
      secret_set tailscale_authkey "$(head -n1 "${kf/#\~/$HOME}")"
      cfg_unset tailscale.authkey_file
    fi
  fi
}

mod_install() {
  if [[ "$(_mode)" == app ]]; then
    ui_msg "Tailscale app" "Install Tailscale from Google Play or F-Droid, sign in, and turn on \"Always-on VPN\" for it in Android settings.
Services will listen on all interfaces; use a strong password for each."
    return 0
  fi
  proot_install
  local tgz work root
  tgz=$(fetch_pinned tailscale)
  [[ "$REZ_DRY_RUN" == 1 ]] && return 0
  root=$(proot_rootfs)
  work=$(mktemp -d)
  tar -xzf "$tgz" -C "$work"
  install -m 755 "$work"/tailscale_*/tailscale "$work"/tailscale_*/tailscaled "$root/usr/local/bin/"
  rm -rf "$work"
  mkdir -p "$root$TS_DIR"
  chmod 700 "$root$TS_DIR"
  ok "tailscale $PIN_TAILSCALE_VERSION installed in Debian"
}

_daemon() { svc_running tailscaled tailscaled; }

mod_start() {
  [[ "$(_mode)" == app ]] && return 0
  SVC_SUPERVISE=1 svc_start tailscaled tailscaled "" -- \
    "${PROOT_CMD[@]}" /usr/local/bin/tailscaled --tun=userspace-networking \
    --state="$TS_DIR/tailscaled.state" --socket="$TS_SOCK" --statedir="$TS_DIR"
  local i state=''
  for i in $(seq 1 15); do
    state=$(ts status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null) && [[ -n "$state" ]] && break
    sleep 1
  done
  if [[ "$state" != Running ]]; then
    _ts_up || warn "tailscale is not logged in yet: run rez tailscale up"
  fi
  _remember_name
}

_ts_up() {
  local -a args=(up --accept-dns=false --hostname="$(cfg_get tailscale.hostname resurrect)")
  local key
  if key=$(secret_get tailscale_authkey); then
    # One-time use: the key is deleted once the node is registered.
    ts "${args[@]}" --auth-key="$key" && secret_del tailscale_authkey && ok "tailscale logged in"
    return
  fi
  [[ $(ui_mode) == none ]] && return 1
  info "open the login link below on any device to add this phone to your tailnet"
  ts "${args[@]}"
}

_remember_name() {
  local name
  name=$(ts status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null | sed 's/\.$//') || true
  [[ -n "$name" ]] && cfg_set tailscale.dnsname "$name"
  return 0
}

mod_stop() {
  [[ "$(_mode)" == app ]] && return 0
  svc_stop tailscaled tailscaled
}

mod_status() {
  if [[ "$(_mode)" == app ]]; then
    printf '%-14s %s\n' tailscale "managed by the Android app"
    return 0
  fi
  local state
  state=$(ts status --json 2>/dev/null | jq -r '.BackendState // "?"' 2>/dev/null || echo "?")
  svc_status_line tailscaled tailscaled "" "$state $(cfg_get tailscale.dnsname "")"
}

mod_health() {
  [[ "$(_mode)" == app ]] && return 0
  _daemon && [[ "$(ts status --json 2>/dev/null | jq -r .BackendState 2>/dev/null)" == Running ]]
}

# tailscale_cert DEST_DIR: fetch/renew the Let's Encrypt cert for this
# device's tailnet name into DEST_DIR/{cert,key}.pem. Exit 0 = changed,
# 1 = error, 2 = unchanged.
tailscale_cert() {
  local out=$1 name root
  name=$(cfg_get tailscale.dnsname "")
  [[ -n "$name" ]] || { _remember_name; name=$(cfg_get tailscale.dnsname ""); }
  [[ -n "$name" ]] || { err "tailscale name unknown (logged in? HTTPS enabled in the admin console?)"; return 1; }
  root=$(proot_rootfs)
  mkdir -p "$root$TS_DIR/certs"
  ts cert --cert-file "$TS_DIR/certs/$name.crt" --key-file "$TS_DIR/certs/$name.key" "$name" >&2 \
    || { err "tailscale cert failed: enable HTTPS certificates in the Tailscale admin console (DNS page)"; return 1; }
  mkdir -p "$out"
  chmod 700 "$out"
  if cmp -s "$root$TS_DIR/certs/$name.crt" "$out/cert.pem"; then return 2; fi
  install -m 600 "$root$TS_DIR/certs/$name.crt" "$out/cert.pem"
  install -m 600 "$root$TS_DIR/certs/$name.key" "$out/key.pem"
  return 0
}

mod_backup() {
  [[ "$(_mode)" == app ]] && return 0
  local root
  root=$(proot_rootfs) || return 0
  mkdir -p "$1"
  # Node state: restores the same identity and address without a new login.
  cp -a "$root$TS_DIR/tailscaled.state" "$1/" 2>/dev/null || true
}

mod_uninstall() {
  [[ "$(_mode)" == app ]] && { info "uninstall the Tailscale app from Android settings"; return 0; }
  local root
  root=$(proot_rootfs) || return 0
  ts logout 2>/dev/null || true
  run_cmd rm -f "$root/usr/local/bin/tailscale" "$root/usr/local/bin/tailscaled"
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "${root:?}$TS_DIR"
  return 0
}

mod_info() {
  if [[ "$(_mode)" == app ]]; then
    echo "Tailscale:  Android app (check it is connected)"
  else
    printf 'Tailscale:  %s (rez tailscale status)\n' "$(cfg_get tailscale.dnsname "not logged in: rez tailscale up")"
  fi
}

mod_cli() {
  case "${1:-}" in
    up) _ts_up; _remember_name ;;
    status) ts status ;;
    ip) ts ip -4 ;;
    cert) tailscale_cert "${2:?usage: rez tailscale cert DIR}"; local rc=$?; ((rc == 2)) && { echo unchanged; return 0; }; return $rc ;;
    *) die "usage: rez tailscale up|status|ip|cert DIR" ;;
  esac
}
