# shellcheck shell=bash
# ntfy: push notifications for every alert resurrect sends.
#
# local (default): ntfy server on this device, deny-all access, three users:
#   admin (you), rez (publish only, used by resurrect), phone (read only).
# external: use an existing ntfy server (e.g. ntfy.sh or your own) instead.

MOD_NAME=ntfy
MOD_DESC="ntfy push notifications (alerts go here)"
MOD_DEPENDS="base"
MOD_PORTS="2586"
MOD_ARCHES="arm64 armv7 amd64"
MOD_RAM_EST_MB=25
MOD_DISK_EST_MB=30
MOD_TESTED="termux-docker (amd64): install, users, publish. Real device: no"

NTFY_DIR=$REZ_DATA_DIR/ntfy
NTFY_BIN=$NTFY_DIR/ntfy

_mode() { cfg_get ntfy.mode local; }
_port() { cfg_get ntfy.port 2586; }
_topic() { cfg_get ntfy.topic alerts; }

# The Go binary needs Android's CA store for any outbound TLS.
_ntfy() { env SSL_CERT_DIR=/system/etc/security/cacerts NTFY_AUTH_FILE="$NTFY_DIR/user.db" "$NTFY_BIN" "$@"; }

mod_configure() {
  local mode
  mode=$(cfg_get ntfy.mode "")
  [[ -n "$mode" ]] || mode=$(ui_menu "ntfy" "Where should alerts be sent?" local \
    local "Run an ntfy server on this phone (private, recommended)" \
    external "Use an existing ntfy server (ntfy.sh or your own)")
  cfg_set ntfy.mode "$mode"
  cfg_set ntfy.topic "$(cfg_get ntfy.topic "$(ui_input "ntfy" "Topic name for alerts" "alerts")")"
  if [[ "$mode" == external ]]; then
    cfg_set ntfy.url "$(cfg_get ntfy.external_url "$(ui_input "ntfy" "Server URL" "https://ntfy.sh" required)")"
    if ! secret_get ntfy_publish_token >/dev/null && [[ $(ui_mode) != none ]]; then
      local t
      t=$(ui_password "ntfy" "Access token for publishing (empty if the topic is open; on ntfy.sh pick an unguessable topic)")
      [[ -n "$t" ]] && secret_set ntfy_publish_token "$t"
    fi
  else
    cfg_set ntfy.url "http://127.0.0.1:$(_port)"
  fi
}

mod_install() {
  [[ "$(_mode)" == external ]] && { ok "using external ntfy at $(cfg_get ntfy.url)"; return 0; }
  local tgz work
  tgz=$(fetch_pinned ntfy)
  [[ "$REZ_DRY_RUN" == 1 ]] && return 0
  mkdir -p "$NTFY_DIR"
  chmod 700 "$NTFY_DIR"
  work=$(mktemp -d)
  tar -xzf "$tgz" -C "$work"
  install -m 755 "$work"/ntfy_*/ntfy "$NTFY_BIN"
  rm -rf "$work"
  _write_config
  _users
}

_write_config() {
  atomic_write "$NTFY_DIR/server.yml" 600 <<EOF
# Written by rez. Docs: https://docs.ntfy.sh/config/
base-url: "http://$(device_host):$(_port)"
listen-http: "$(service_bind):$(_port)"
cache-file: "$NTFY_DIR/cache.db"
cache-duration: "24h"
auth-file: "$NTFY_DIR/user.db"
auth-default-access: "deny-all"
behind-proxy: false
attachment-cache-dir: ""
enable-signup: false
enable-login: true
log-level: warn
EOF
}

_user_exists() { _ntfy user list 2>&1 | grep -qE "^user $1 "; }

# Users are created with passwords from the secrets dir; NTFY_PASSWORD keeps
# them off the command line.
_users() {
  local topic pw
  topic=$(_topic)
  if ! _user_exists admin; then
    pw=$(secret_ensure ntfy_admin_password 24)
    NTFY_PASSWORD=$pw _ntfy user add --role=admin admin >/dev/null
  fi
  if ! _user_exists rez; then
    NTFY_PASSWORD=$(rand_token 32) _ntfy user add rez >/dev/null
  fi
  _ntfy access rez "$topic" write-only >/dev/null
  if ! secret_get ntfy_publish_token >/dev/null; then
    local tok
    tok=$(_ntfy token add rez 2>&1 | grep -oE 'tk_[A-Za-z0-9]+' | head -n1)
    [[ -n "$tok" ]] || die "could not create the ntfy publish token"
    secret_set ntfy_publish_token "$tok"
  fi
  if ! _user_exists phone; then
    pw=$(secret_ensure ntfy_phone_password 20)
    NTFY_PASSWORD=$pw _ntfy user add phone >/dev/null
  fi
  _ntfy access phone "$topic" read-only >/dev/null
  ok "ntfy users ready (admin, rez publish-only, phone read-only on '$topic')"
}

mod_start() {
  [[ "$(_mode)" == external ]] && return 0
  svc_start ntfy ntfy "serve" -- nice -n 10 env SSL_CERT_DIR=/system/etc/security/cacerts \
    "$NTFY_BIN" serve --config "$NTFY_DIR/server.yml"
}

mod_stop() {
  [[ "$(_mode)" == external ]] && return 0
  svc_stop ntfy ntfy "serve"
}

mod_status() {
  if [[ "$(_mode)" == external ]]; then
    printf '%-14s %s\n' ntfy "external: $(cfg_get ntfy.url)"
    return 0
  fi
  svc_status_line ntfy ntfy "serve" "port $(_port), topic $(_topic)"
}

mod_health() {
  [[ "$(_mode)" == external ]] && return 0
  svc_running ntfy ntfy "serve" && curl -fsS -m 5 "http://127.0.0.1:$(_port)/v1/health" | grep -q '"healthy":true'
}

mod_backup() {
  [[ "$(_mode)" == external ]] && return 0
  mkdir -p "$1"
  cp -a "$NTFY_DIR/server.yml" "$1/"
  sqlite3 "$NTFY_DIR/user.db" ".backup '$1/user.db'"
}

mod_restore_check() {
  [[ -f "$1/user.db" ]] || return 0
  [[ "$(sqlite3 "$1/user.db" 'PRAGMA integrity_check;')" == ok ]]
}

mod_uninstall() {
  run rm -f "$NTFY_BIN"
  [[ "${REZ_PURGE:-0}" == 1 ]] && run rm -rf "$NTFY_DIR"
  return 0
}

mod_info() {
  if [[ "$(_mode)" == external ]]; then
    printf 'ntfy:       %s/%s\n' "$(cfg_get ntfy.url)" "$(_topic)"
    return
  fi
  printf 'ntfy:       http://%s:%s  topic "%s"\n' "$(device_host)" "$(_port)" "$(_topic)"
  printf '            phone app: add server above, user "phone", password: rez ntfy show-phone-password\n'
}

mod_cli() {
  case "${1:-}" in
    test) notify_send "Test from resurrect" "If you can read this, alerts work." 3 white_check_mark; ok "sent (check your phone)" ;;
    show-phone-password) secret_get ntfy_phone_password; echo ;;
    show-admin-password) secret_get ntfy_admin_password; echo ;;
    *) die "usage: rez ntfy test|show-phone-password|show-admin-password" ;;
  esac
}
