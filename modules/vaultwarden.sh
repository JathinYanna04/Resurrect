# shellcheck shell=bash
# vaultwarden: Bitwarden-compatible password manager with HTTPS.
#
# * Native static binary (extracted from the official Alpine image, pinned by
#   digest), no proot.
# * HTTPS: a real Let's Encrypt cert from `tailscale cert` (needs Tailscale in
#   built-in mode), or a self-signed cert as a fallback.
# * Sign-ups: open only until the first account exists. A cron check closes
#   them automatically and verifies a test sign-up is refused.
# * Admin page token stored as an argon2id hash; the password is in
#   ~/.config/resurrect/secrets/vaultwarden_admin_password.

MOD_NAME=vaultwarden
MOD_DESC="Vaultwarden password manager (HTTPS, sign-ups closed after setup)"
MOD_DEPENDS="base"
MOD_PORTS="8222"
MOD_ARCHES="arm64 armv7 amd64"
MOD_RAM_EST_MB=30
MOD_DISK_EST_MB=120
MOD_TESTED="termux-docker (amd64): image extraction, HTTPS (self-signed), sign-up close + verify, argon2 admin token. Tailscale cert: real device only"

VW_DIR=$REZ_DATA_DIR/vaultwarden
VW_ENV=$REZ_CONFIG_DIR/vaultwarden.env

_port() { cfg_get vaultwarden.port 8222; }
_https() { cfg_get vaultwarden.https tailscale; }
_scheme_host() { printf 'https://%s:%s' "$(cfg_get vaultwarden.domain "$(device_host)")" "$(_port)"; }

mod_configure() {
  local https
  https=$(cfg_get vaultwarden.https "")
  if [[ -z "$https" ]]; then
    if [[ "$(cfg_get tailscale.mode "")" == proot ]] && csv_has "${REZ_SETUP_MODULES:-},$(cfg_get modules "")" tailscale; then
      https=tailscale
    else
      https=selfsigned
    fi
    [[ $(ui_mode) != none ]] && https=$(ui_menu "Vaultwarden HTTPS" \
      "Bitwarden apps need HTTPS. A Tailscale certificate is trusted everywhere; a self-signed one must be installed on each device." \
      "$https" tailscale "Tailscale certificate (needs built-in Tailscale, HTTPS enabled in its admin console)" \
      selfsigned "Self-signed certificate")
  fi
  cfg_set vaultwarden.https "$https"
}

mod_install() {
  local arch digest
  arch=$(go_arch)
  digest=${PIN_VAULTWARDEN_SHA256[$arch]:-}
  [[ -n "$digest" ]] || die "Vaultwarden has no build for $(uname -m)"
  if [[ -x "$VW_DIR/vaultwarden" && "$(cat "$VW_DIR/.version" 2>/dev/null)" == "$PIN_VAULTWARDEN_VERSION" ]]; then
    ok "vaultwarden $PIN_VAULTWARDEN_VERSION already installed"
  else
    info "fetching vaultwarden $PIN_VAULTWARDEN_VERSION ($arch image, ~40 MB)"
    [[ "$REZ_DRY_RUN" == 1 ]] || {
      local stage="$VW_DIR.new"
      rm -rf "$stage"
      fetch_image_files "$PIN_VAULTWARDEN_IMAGE" "$digest" "$stage" vaultwarden web-vault
      mkdir -p "$VW_DIR"
      rm -rf "$VW_DIR/web-vault"
      mv "$stage/vaultwarden" "$VW_DIR/vaultwarden"
      mv "$stage/web-vault" "$VW_DIR/web-vault"
      rm -rf "$stage"
      echo "$PIN_VAULTWARDEN_VERSION" >"$VW_DIR/.version"
    }
  fi
  ensure_dir 700 "$VW_DIR" "$VW_DIR/data" "$VW_DIR/tls"
  _admin_token
  _cert || true
  # First install: sign-ups open until the first account exists.
  [[ -n "$(cfg_get vaultwarden.signups "")" ]] || cfg_set vaultwarden.signups open
  _write_env
}

_admin_token() {
  [[ -f "$VW_DIR/admin_token" ]] && return 0
  local pw salt hash
  pw=$(secret_ensure vaultwarden_admin_password 32)
  salt=$(rand_token 22)
  if have argon2; then
    # Same parameters as `vaultwarden hash` (Bitwarden preset).
    hash=$(printf '%s' "$pw" | argon2 "$salt" -e -id -k 65540 -t 3 -p 4)
  else
    warn "argon2 not found: the admin token is stored in plain text (pkg install argon2 to fix)"
    hash=$pw
  fi
  printf '%s' "$hash" | atomic_write "$VW_DIR/admin_token" 600
}

# _cert: make sure tls/cert.pem exists. Returns 0 if it changed.
_cert() {
  local rc=0
  case "$(_https)" in
    tailscale)
      ( module_load tailscale; tailscale_cert "$VW_DIR/tls" ) || rc=$?
      case $rc in
        0) ok "tailscale certificate installed"; return 0 ;;
        2) return 1 ;;
        *) warn "no tailscale certificate yet; using a temporary self-signed one"; _selfsigned; return 0 ;;
      esac
      ;;
    selfsigned)
      [[ -s "$VW_DIR/tls/cert.pem" ]] && return 1
      _selfsigned
      ;;
  esac
}

_selfsigned() {
  local host
  host=$(device_host)
  run_cmd openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$VW_DIR/tls/key.pem" -out "$VW_DIR/tls/cert.pem" \
    -subj "/CN=$host" -addext "subjectAltName=DNS:$host,DNS:localhost,IP:127.0.0.1" 2>/dev/null
  run_cmd chmod 600 "$VW_DIR/tls/key.pem" "$VW_DIR/tls/cert.pem"
}

_write_env() {
  local signups=false token='<generated at install>'
  [[ "$REZ_DRY_RUN" == 1 ]] || token=$(cat "$VW_DIR/admin_token")
  [[ "$(cfg_get vaultwarden.signups closed)" == open ]] && signups=true
  atomic_write "$VW_ENV" 600 <<EOF
DATA_FOLDER=$VW_DIR/data
WEB_VAULT_FOLDER=$VW_DIR/web-vault
WEB_VAULT_ENABLED=true
ROCKET_ADDRESS=$(service_bind)
ROCKET_PORT=$(_port)
ROCKET_WORKERS=4
DATABASE_MAX_CONNS=4
DOMAIN=$(_scheme_host)
SIGNUPS_ALLOWED=$signups
INVITATIONS_ALLOWED=false
SHOW_PASSWORD_HINT=false
ADMIN_TOKEN=$token
${TLS_ENV[0]}
${TLS_ENV[1]}
LOG_LEVEL=warn
EXTENDED_LOGGING=true
ROCKET_TLS={certs="$VW_DIR/tls/cert.pem",key="$VW_DIR/tls/key.pem"}
EOF
}

_env_array() {
  SVC_ENV=()
  [[ -f "$VW_ENV" ]] || return 0   # dry run: nothing was written
  local line
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != \#* ]] && SVC_ENV+=("$line")
  done <"$VW_ENV"
}

mod_start() {
  [[ -f "$VW_ENV" ]] || _write_env
  _env_array
  SVC_SUPERVISE=1 svc_start vaultwarden vaultwarden "" -- "$VW_DIR/vaultwarden"
}

mod_stop() { svc_stop vaultwarden vaultwarden; }

_url() { printf 'https://127.0.0.1:%s' "$(_port)"; }

mod_status() {
  svc_status_line vaultwarden vaultwarden "" "$(_scheme_host)  sign-ups: $(cfg_get vaultwarden.signups closed)"
}

mod_health() {
  svc_running vaultwarden vaultwarden && curl -fsSk -m 5 "$(_url)/alive" >/dev/null
}

_users() { sqlite3 "$VW_DIR/data/db.sqlite3" 'SELECT COUNT(*) FROM users;' 2>/dev/null || echo 0; }

# _signup_refused: true if the server rejects a new registration.
_signup_refused() {
  local body r
  body='{"email":"signup-probe@example.invalid","name":"probe","receiveMarketingEmails":false}'
  r=$(curl -sk -m 10 -H 'Content-Type: application/json' -d "$body" \
    "$(_url)/identity/accounts/register/send-verification-email" 2>/dev/null)
  grep -qi 'not allowed' <<<"$r"
}

vw_close_signups() {
  cfg_set vaultwarden.signups closed
  cfg_unset vaultwarden.signups_manual
  _write_env
  mod_stop >/dev/null
  mod_start >/dev/null || die "vaultwarden did not restart"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do mod_health && break; sleep 1; done
  if _signup_refused; then
    ok "sign-ups closed (a test registration was refused)"
  else
    err "sign-ups were turned off but a test registration was NOT refused; check $(_scheme_host)/admin"
    return 1
  fi
}

vw_open_signups() {
  cfg_set vaultwarden.signups open
  _write_env
  mod_stop >/dev/null
  mod_start >/dev/null
  warn "sign-ups are OPEN. Anyone who can reach $(_scheme_host) can register. Close with: rez vaultwarden close-signups"
}

# Called from cron: close sign-ups once the first account exists.
vw_autoclose() {
  [[ "$(cfg_get vaultwarden.signups closed)" == open ]] || return 0
  [[ "$(cfg_get vaultwarden.signups_manual "")" == yes ]] && return 0
  (($(_users) >= 1)) || return 0
  if vw_close_signups; then
    notify_send "Vaultwarden sign-ups closed" "An account exists, so new registrations are now refused." 3 lock
    ( base_sync_boot_and_cron ) >/dev/null 2>&1 || true
  else
    notify_send "Vaultwarden sign-ups NOT closed" "Automatic close failed. Run: rez vaultwarden close-signups" 5 warning
  fi
}

vw_renew_cert() {
  [[ "$(_https)" == tailscale ]] || return 0
  if _cert; then
    info "certificate renewed, restarting"
    mod_stop >/dev/null
    mod_start >/dev/null
  fi
}

mod_cron() {
  [[ "$(_https)" == tailscale ]] && echo "17 4 * * 1 $(rez_cmd) vaultwarden renew-cert >>$REZ_LOG_DIR/vaultwarden-cert.log 2>&1"
  [[ "$(cfg_get vaultwarden.signups closed)" == open ]] && echo "*/5 * * * * $(rez_cmd) vaultwarden autoclose >>$REZ_LOG_DIR/vaultwarden.log 2>&1"
  return 0
}

mod_backup() {
  local d=$1 x
  mkdir -p "$d"
  sqlite3 "$VW_DIR/data/db.sqlite3" ".backup '$d/db.sqlite3'"
  for x in rsa_key.pem rsa_key.pub.pem config.json; do
    [[ -e "$VW_DIR/data/$x" ]] && cp -a "$VW_DIR/data/$x" "$d/"
  done
  for x in attachments sends; do
    [[ -d "$VW_DIR/data/$x" ]] && cp -a "$VW_DIR/data/$x" "$d/"
  done
  cp -a "$VW_DIR/admin_token" "$d/"
  return 0
}

mod_restore_check() {
  [[ -f "$1/db.sqlite3" ]] || { echo "no database in backup"; return 1; }
  [[ "$(sqlite3 "$1/db.sqlite3" 'PRAGMA integrity_check;')" == ok ]] || { echo "integrity check failed"; return 1; }
  echo "users: $(sqlite3 "$1/db.sqlite3" 'SELECT COUNT(*) FROM users;')"
}

mod_uninstall() {
  run_cmd rm -f "$VW_DIR/vaultwarden" "$VW_ENV"
  run_cmd rm -rf "$VW_DIR/web-vault"
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$VW_DIR"
  return 0
}

mod_info() {
  printf 'Vaultwarden: %s  (admin page /admin, password: rez vaultwarden show-admin-password)\n' "$(_scheme_host)"
  if [[ "$(cfg_get vaultwarden.signups closed)" == open ]]; then
    printf '             Create your account now; sign-ups close automatically within 5 minutes after.\n'
  fi
  [[ "$(_https)" == selfsigned ]] && printf '             Self-signed cert: install %s on your devices (docs/security.md).\n' "$VW_DIR/tls/cert.pem"
  return 0
}

mod_cli() {
  case "${1:-}" in
    close-signups) vw_close_signups; base_sync_boot_and_cron ;;
    open-signups) cfg_set vaultwarden.signups_manual yes; vw_open_signups; base_sync_boot_and_cron ;;
    autoclose) vw_autoclose ;;
    renew-cert) vw_renew_cert ;;
    show-admin-password) secret_get vaultwarden_admin_password; echo ;;
    users) _users ;;
    *) die "usage: rez vaultwarden close-signups|open-signups|renew-cert|show-admin-password|users" ;;
  esac
}
