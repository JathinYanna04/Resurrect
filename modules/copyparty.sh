# shellcheck shell=bash
# copyparty: file sharing in the browser, WebDAV, uploads. Pure Python, run
# from its official single-file build (pinned, checksum-verified).

MOD_NAME=copyparty
MOD_DESC="copyparty file sharing (web, WebDAV, uploads)"
MOD_DEPENDS="base"
MOD_PORTS="3923"
MOD_RAM_EST_MB=40
MOD_DISK_EST_MB=10
MOD_TESTED="termux-docker (amd64): install, start, auth (anonymous refused). Real device: no"

CP_DIR=$REZ_DATA_DIR/copyparty

_port() { cfg_get copyparty.port 3923; }
_share() { local p; p=$(cfg_get copyparty.path "$HOME/share"); echo "${p/#\~/$HOME}"; }

mod_configure() {
  local def="$HOME/share"
  [[ -n "${DEV_SD_WRITABLE_PATH:-}" ]] && def="$DEV_SD_WRITABLE_PATH/share"
  cfg_set copyparty.path "$(cfg_get copyparty.path "$(ui_input "copyparty" "Folder to share" "$def")")"
}

mod_install() {
  ensure_dir 700 "$CP_DIR"
  fetch_verified "$PIN_COPYPARTY_URL" "$PIN_COPYPARTY_SHA256" "$CP_DIR/copyparty-sfx.py"
  ensure_dir 755 "$(_share)"
  local pw
  pw=$(secret_ensure copyparty_password 20)
  # nih: do not reveal the phone's hostname in listings.
  atomic_write "$CP_DIR/copyparty.conf" 600 <<EOF
# Written by rez. Docs: https://github.com/9001/copyparty
[global]
  i: $(service_bind)
  p: $(_port)
  no-robots
  nih
  hist: $CP_DIR/hist

[accounts]
  admin: $pw

[/]
  $(_share)
  accs:
    rwmd: admin
EOF
}

CP_EXE=copyparty-sfx.py

mod_start() {
  svc_start copyparty "$CP_EXE" "" -- nice -n 10 "$PREFIX/bin/python3" "$CP_DIR/copyparty-sfx.py" -c "$CP_DIR/copyparty.conf"
}

mod_stop() { svc_stop copyparty "$CP_EXE"; }

mod_status() { svc_status_line copyparty "$CP_EXE" "" "port $(_port), sharing $(_share)"; }

mod_health() { svc_running copyparty "$CP_EXE" && port_open 127.0.0.1 "$(_port)"; }

mod_backup() {
  mkdir -p "$1"
  cp -a "$CP_DIR/copyparty.conf" "$1/"
}

mod_uninstall() {
  run_cmd rm -f "$CP_DIR/copyparty-sfx.py"
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$CP_DIR"
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
