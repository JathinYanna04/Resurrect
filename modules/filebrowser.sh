# shellcheck shell=bash
# filebrowser: simple web file manager. Alternative to copyparty.

MOD_NAME=filebrowser
MOD_DESC="File Browser web file manager (alternative to copyparty)"
MOD_DEPENDS="base"
MOD_PORTS="8085"
MOD_RAM_EST_MB=30
MOD_DISK_EST_MB=40
MOD_TESTED="termux-docker (amd64): install, user creation, start. Real device: no"

FB_DIR=$REZ_DATA_DIR/filebrowser

_port() { cfg_get filebrowser.port 8085; }
_root() { local p; p=$(cfg_get filebrowser.path "$HOME/share"); echo "${p/#\~/$HOME}"; }
_fb() { "$FB_DIR/filebrowser" -d "$FB_DIR/filebrowser.db" "$@"; }

mod_configure() {
  local def="$HOME/share"
  [[ -n "${DEV_SD_WRITABLE_PATH:-}" ]] && def="$DEV_SD_WRITABLE_PATH/share"
  cfg_set filebrowser.path "$(cfg_get filebrowser.path "$(ui_input "File Browser" "Folder to serve" "$def")")"
}

mod_install() {
  local tgz work
  tgz=$(fetch_pinned filebrowser)
  [[ "$REZ_DRY_RUN" == 1 ]] && return 0
  ensure_dir 700 "$FB_DIR"
  ensure_dir 755 "$(_root)"
  work=$(mktemp -d)
  tar -xzf "$tgz" -C "$work"
  install -m 755 "$work/filebrowser" "$FB_DIR/filebrowser"
  rm -rf "$work"
  if [[ ! -f "$FB_DIR/filebrowser.db" ]]; then
    _fb config init --address "$(service_bind)" --port "$(_port)" --root "$(_root)" >/dev/null
    _fb users add admin "$(secret_ensure filebrowser_password 20)" --perm.admin >/dev/null
  fi
}

mod_start() { svc_start filebrowser filebrowser "" -- nice -n 10 "$FB_DIR/filebrowser" -d "$FB_DIR/filebrowser.db"; }
mod_stop() { svc_stop filebrowser filebrowser; }
mod_status() { svc_status_line filebrowser filebrowser "" "port $(_port), serving $(_root)"; }
mod_health() { svc_running filebrowser filebrowser && port_open 127.0.0.1 "$(_port)"; }

mod_backup() {
  mkdir -p "$1"
  # Users and settings only. Copied live: small and rarely written.
  cp -a "$FB_DIR/filebrowser.db" "$1/"
}

mod_uninstall() {
  run rm -f "$FB_DIR/filebrowser"
  [[ "${REZ_PURGE:-0}" == 1 ]] && run rm -rf "$FB_DIR"
  return 0
}

mod_info() {
  printf 'Files:      http://%s:%s  user admin, password: rez filebrowser show-password\n' "$(device_host)" "$(_port)"
}

mod_cli() {
  case "${1:-}" in
    show-password) secret_get filebrowser_password; echo ;;
    *) die "usage: rez filebrowser show-password" ;;
  esac
}
