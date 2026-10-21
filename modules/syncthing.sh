# shellcheck shell=bash
# syncthing: continuous peer-to-peer folder sync.

MOD_NAME=syncthing
MOD_DESC="Syncthing folder sync between your devices"
MOD_DEPENDS="base"
MOD_PORTS="8384 22000"
MOD_RAM_EST_MB=40
MOD_DISK_EST_MB=40
MOD_TESTED="termux-docker (amd64): install, GUI login required, single process. Real device: no"

ST_HOME=$REZ_DATA_DIR/syncthing

_gui() { printf '%s:%s' "$(service_bind)" "$(cfg_get syncthing.gui_port 8384)"; }

mod_install() {
  is_termux && run_cmd pkg install -y syncthing
  if [[ ! -f "$ST_HOME/config.xml" ]]; then
    ensure_dir 700 "$ST_HOME"
    run_cmd syncthing generate --home="$ST_HOME" --gui-user=admin \
      --gui-password="$(secret_ensure syncthing_password 20)" >/dev/null
  fi
}

mod_start() {
  # Syncthing normally runs a monitor process plus the real one (two
  # identical "syncthing serve" processes; --no-restart does not prevent it
  # in 2.x). STMONITORED=yes says "you are already supervised": one process,
  # and when it exits to restart itself, resurrect's supervisor restarts it.
  SVC_ENV=(STNOUPGRADE=1 STMONITORED=yes)
  SVC_SUPERVISE=1 svc_start syncthing syncthing "serve" -- nice -n 10 syncthing serve --no-browser \
    --home="$ST_HOME" --gui-address="$(_gui)"
}

mod_stop() { svc_stop syncthing syncthing "serve"; }
mod_status() { svc_status_line syncthing syncthing "serve" "GUI $(_gui)"; }
mod_health() { svc_running syncthing syncthing "serve"; }

mod_backup() {
  mkdir -p "$1"
  # Identity and settings; synced data lives in its own folders.
  cp -a "$ST_HOME/config.xml" "$ST_HOME/cert.pem" "$ST_HOME/key.pem" "$1/" 2>/dev/null || true
}

mod_uninstall() {
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$ST_HOME"
  info "the syncthing package and synced folders were left in place"
}

mod_info() {
  printf 'Syncthing:  http://%s:%s  user admin, password: rez syncthing show-password\n' \
    "$(device_host)" "$(cfg_get syncthing.gui_port 8384)"
}

mod_cli() {
  case "${1:-}" in
    show-password) secret_get syncthing_password; echo ;;
    *) die "usage: rez syncthing show-password" ;;
  esac
}
