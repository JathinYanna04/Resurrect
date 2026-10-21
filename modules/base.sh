# shellcheck shell=bash
# base: Termux packages, sshd with key-only login, wake lock, cron, startup.
# Every other module depends on it.

MOD_NAME=base
MOD_DESC="Termux packages, SSH (keys only), wake lock, cron, boot startup"
MOD_PORTS="8022"
MOD_RAM_EST_MB=10
MOD_DISK_EST_MB=150
MOD_TESTED="termux-docker: packages, key-only sshd, cron block, boot script, boot lock. Termux:Boot itself: real device only"

BASE_PKGS=(openssh cronie util-linux procps dialog jq curl openssl-tool sqlite python rsync iproute2 termux-tools)

_sshd_config() { echo "$PREFIX/etc/ssh/sshd_config"; }
_authkeys() { echo "$HOME/.ssh/authorized_keys"; }

_has_key() { [[ -s "$(_authkeys)" ]] && grep -qE '^(ssh-|ecdsa-|sk-)' "$(_authkeys)"; }

mod_configure() {
  local key
  key=$(cfg_get base.ssh_pubkey "")
  local kf
  kf=$(cfg_get base.ssh_pubkey_file "")
  if [[ -z "$key" && -n "$kf" ]]; then
    kf=${kf/#\~/$HOME}
    key=$(head -n1 "$kf") || die "cannot read base.ssh_pubkey_file $kf"
  fi
  if [[ -z "$key" ]] && ! _has_key && [[ $(ui_mode) != none ]]; then
    key=$(ui_input "SSH key" "Paste the PUBLIC key of the computer you will manage this phone from
(the one line in ~/.ssh/id_ed25519.pub; create it with: ssh-keygen -t ed25519).
Password login stays off. Leave empty to add a key later with: rez base add-key" "")
  fi
  [[ -n "$key" ]] && cfg_set base.ssh_pubkey "$key"
  return 0
}

base_add_key() {
  local key=$1
  [[ "$key" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-[a-z0-9]+|sk-[a-z0-9@.-]+)\ [A-Za-z0-9+/=]+ ]] || die "that does not look like an SSH public key"
  ensure_dir 700 "$HOME/.ssh"
  touch "$(_authkeys)"
  grep -qF "$key" "$(_authkeys)" || run_cmd sh -c "printf '%s\n' \"\$1\" >> \"\$2\"" _ "$key" "$(_authkeys)"
  run_cmd chmod 600 "$(_authkeys)"
  ok "SSH key added"
}

# Key-only login. Termux's sshd runs as the app user, so there is no root
# login to disable; passwords are what we turn off.
_harden_sshd() {
  local f
  f=$(_sshd_config)
  [[ -f "$f" ]] || return 0
  local k
  for k in PasswordAuthentication KbdInteractiveAuthentication; do
    if grep -qE "^[#[:space:]]*$k" "$f"; then
      run_cmd sed -i -E "s/^[#[:space:]]*$k.*/$k no/" "$f"
    else
      run_cmd sh -c "echo '$k no' >> '$f'"
    fi
  done
  grep -qE '^PubkeyAuthentication' "$f" || run_cmd sh -c "echo 'PubkeyAuthentication yes' >> '$f'"
}

mod_install() {
  if is_termux; then
    run_cmd pkg update -y
    run_cmd pkg install -y "${BASE_PKGS[@]}"
  else
    warn "not Termux: skipping package installation"
  fi
  local key
  key=$(cfg_get base.ssh_pubkey "")
  [[ -n "$key" ]] && base_add_key "$key"
  _harden_sshd
  rez_init_dirs
  # Wrapper so `rez` works from any shell and at boot (no termux-exec needed).
  if [[ -d "$PREFIX/bin" && -w "$PREFIX/bin" ]]; then
    printf '#!%s/bin/sh\nexec %s/bin/bash %s/bin/rez "$@"\n' "$PREFIX" "$PREFIX" "$REZ_ROOT" \
      | atomic_write "$PREFIX/bin/rez" 755
  fi
}

_sshd_up() { svc_running sshd sshd; }

mod_start() {
  if have termux-wake-lock; then run_cmd timeout 10 termux-wake-lock || warn "could not take the wake lock"; fi
  if _has_key; then
    if _sshd_up; then ok "sshd already running"; else run_cmd sshd && ok "sshd started on port 8022"; fi
  else
    warn "sshd not started: no SSH key yet (rez base add-key 'ssh-ed25519 AAAA...')"
  fi
  # crond daemonizes itself; full path because PATH is minimal at boot.
  if svc_running crond crond; then ok "crond already running"
  elif [[ -x "$PREFIX/bin/crond" ]]; then run_cmd "$PREFIX/bin/crond" && ok "crond started"
  fi
}

mod_stop() {
  # Stopping sshd would cut off the session you are probably using.
  info "base: leaving sshd and crond running (stop them by hand with pkill -x sshd / crond)"
  if have termux-wake-unlock; then run_cmd timeout 10 termux-wake-unlock || true; fi
  return 0
}

mod_status() {
  local rc=0
  svc_status_line sshd sshd "" "port 8022$(_has_key || echo ', NO KEY')" || rc=1
  svc_status_line crond crond "" "" || rc=1
  return $rc
}

mod_health() {
  _has_key || return 0
  _sshd_up && port_open 127.0.0.1 8022 && svc_running crond crond
}

mod_doctor() {
  local f
  f=$(_sshd_config)
  if [[ -f "$f" ]] && grep -qE '^PasswordAuthentication no' "$f"; then
    printf '  %sPASS%s ssh password login disabled\n' "$_c_grn" "$_c_off"
  elif [[ -f "$f" ]]; then
    printf '  %sFAIL%s ssh password login is enabled (run_cmd rez install base)\n' "$_c_red" "$_c_off"
  fi
}

mod_backup() {
  local d=$1
  mkdir -p "$d"
  cp -a "$(_authkeys)" "$d/" 2>/dev/null || true
  cp -a "$(_sshd_config)" "$d/" 2>/dev/null || true
  cp -a "$REZ_CONFIG_FILE" "$d/resurrect.conf"
  crontab -l >"$d/crontab" 2>/dev/null || true
}

mod_uninstall() {
  run_cmd rm -f "$REZ_BOOT_DIR/resurrect" "$PREFIX/bin/rez"
  printf '' | cron_install_block
  info "packages and SSH keys were left in place"
}

mod_info() {
  printf 'SSH:        ssh -p 8022 %s@%s\n' "$(id -un 2>/dev/null || echo user)" "$(device_host)"
}

mod_cli() {
  case "${1:-}" in
    add-key) shift; base_add_key "${*:?usage: rez base add-key 'ssh-ed25519 AAAA... comment'}" ;;
    *) die "usage: rez base add-key 'ssh-ed25519 AAAA...'" ;;
  esac
}
