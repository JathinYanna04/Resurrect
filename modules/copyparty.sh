# shellcheck shell=bash
# copyparty: file sharing in the browser, WebDAV, uploads. Pure Python.

MOD_NAME=copyparty
MOD_DESC="copyparty file sharing (web, WebDAV, uploads)"
MOD_DEPENDS="base"
MOD_PORTS="3923"
MOD_RAM_EST_MB=40
MOD_DISK_EST_MB=10
MOD_TESTED="termux-docker (amd64): pip install with hashes, start, login. Real device: no"

CP_DIR=$REZ_DATA_DIR/copyparty

_port() { cfg_get copyparty.port 3923; }
_share() { local p; p=$(cfg_get copyparty.path "$HOME/share"); echo "${p/#\~/$HOME}"; }

mod_configure() {
  local def="$HOME/share"
  [[ -n "${DEV_SD_WRITABLE_PATH:-}" ]] && def="$DEV_SD_WRITABLE_PATH/share"
  cfg_set copyparty.path "$(cfg_get copyparty.path "$(ui_input "copyparty" "Folder to share" "$def")")"
}

mod_install() {
  local req
  req=$(mktemp)
  printf 'copyparty==%s --hash=sha256:%s\n' "$PIN_COPYPARTY_VERSION" "$PIN_COPYPARTY_WHEEL_SHA256" >"$req"
  run python3 -m pip install --quiet --require-hashes --no-deps --only-binary=:all: -r "$req"
  rm -f "$req"
  ensure_dir 700 "$CP_DIR"
  ensure_dir 755 "$(_share)"
  local pw
  pw=$(secret_ensure copyparty_password 20)
  atomic_write "$CP_DIR/copyparty.conf" 600 <<EOF
# Written by rez. Docs: https://github.com/9001/copyparty
[global]
  i: $(service_bind)
  p: $(_port)
  no-robots
  hist: $CP_DIR/hist

[accounts]
  admin: $pw

[/]
  $(_share)
  accs:
    rwmd: admin
EOF
}

mod_start() {
  svc_start copyparty copyparty "" -- nice -n 10 "$PREFIX/bin/python3" -m copyparty -c "$CP_DIR/copyparty.conf"
}

mod_stop() { svc_stop copyparty copyparty; }

mod_status() { svc_status_line copyparty copyparty "" "port $(_port), sharing $(_share)"; }

mod_health() { svc_running copyparty copyparty && port_open 127.0.0.1 "$(_port)"; }

mod_backup() {
  mkdir -p "$1"
  cp -a "$CP_DIR/copyparty.conf" "$1/"
}

mod_uninstall() {
  run python3 -m pip uninstall -y copyparty
  [[ "${REZ_PURGE:-0}" == 1 ]] && run rm -rf "$CP_DIR"
  info "shared files in $(_share) were left in place"
}

mod_info() {
  printf 'Files:      http://%s:%s  user admin, password: rez copyparty show-password\n' "$(device_host)" "$(_port)"
}

mod_cli() {
  case "${1:-}" in
    show-password) secret_get copyparty_password; echo ;;
    *) die "usage: rez copyparty show-password" ;;
  esac
}
