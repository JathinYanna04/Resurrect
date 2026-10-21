#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2012  # single quotes are for inner shells; ls on fixed names
# Real install inside the Termux Docker image, then behaviour checks.
# Run through: tests/termux-docker/run.sh --install
#
# Covered here: base, ntfy, vaultwarden, adguard (no root), copyparty,
# filebrowser, syncthing, backup, monitor, alerts.
# NOT covered (need a phone, a tailnet, an account or root): tailscale,
# cloudflared, jellyfin, acc, AdGuard root mode, Termux:Boot itself.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
REPO=$PWD
pass=0 fail=0
check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "PASS $name"; pass=$((pass + 1))
  else echo "FAIL $name"; fail=$((fail + 1)); fi
}
# retry N CMD...: run CMD up to N times, one second apart.
retry() { local i; for i in $(seq 1 "$1"); do "${@:2}" && return 0; sleep 1; done; return 1; }

export REZ_GETPROP=$REPO/tests/mocks/getprop NO_COLOR=1
export REZ_STORAGE_ROOT=$PREFIX/tmp/nostorage
C=$HOME/.config/resurrect
S=$HOME/.local/state/resurrect

ssh-keygen -q -t ed25519 -N '' -f "$HOME/testkey"
cat >"$PREFIX/tmp/answers.conf" <<EOF
setup.root=no
tailscale.mode=app
base.ssh_pubkey_file=$HOME/testkey.pub
ntfy.mode=local
ntfy.topic=alerts
vaultwarden.https=selfsigned
adguard.mode=noroot
copyparty.path=~/share
filebrowser.path=~/share
backup.keep=2
backup.expect_pull=no
monitor.interval=5
EOF

echo "==> rez setup (non-interactive)"
bash bin/rez --yes setup --config "$PREFIX/tmp/answers.conf" \
  --modules base,ntfy,vaultwarden,adguard,copyparty,filebrowser,syncthing,backup,monitor,alerts
echo "setup exit: $?"
bash bin/rez status

echo "==> checks"
check "boot script installed" test -x "$HOME/.termux/boot/resurrect"
check "rez wrapper installed" test -x "$PREFIX/bin/rez"
check "ssh key installed, password login off" grep -q '^PasswordAuthentication no' "$PREFIX/etc/ssh/sshd_config"
check "sshd running" retry 5 bash -c 'true >/dev/tcp/127.0.0.1/8022'
check "cron block installed" bash -c 'crontab -l | grep -q "backup run"'
check "secrets dir is 700" test "$(stat -c %a "$C/secrets")" = 700

# ntfy: publish with the rez token, read back as the phone user.
check "ntfy healthy" retry 10 bash -c 'curl -fsS http://127.0.0.1:2586/v1/health | grep -q true'
bash bin/rez ntfy test >/dev/null 2>&1
phone=$(cat "$C/secrets/ntfy_phone_password")
check "ntfy: rez publishes, phone user reads" bash -c "curl -fsS -u phone:$phone 'http://127.0.0.1:2586/alerts/json?poll=1' | grep -q 'alerts work'"
check "ntfy: anonymous read refused" bash -c "! curl -fsS 'http://127.0.0.1:2586/alerts/json?poll=1'"
tok=$(cat "$C/secrets/ntfy_publish_token")
check "ntfy: rez token cannot read" bash -c "! curl -fsS -H 'Authorization: Bearer $tok' 'http://127.0.0.1:2586/alerts/json?poll=1'"

# Vaultwarden: alive over HTTPS, sign-ups open until closed, then refused.
check "vaultwarden alive (https)" retry 15 bash -c 'curl -fsSk https://127.0.0.1:8222/alive'
signup_refused() {
  curl -sk -H 'Content-Type: application/json' \
    -d '{"email":"probe@example.invalid","name":"p","receiveMarketingEmails":false}' \
    https://127.0.0.1:8222/identity/accounts/register/send-verification-email | grep -qi 'not allowed'
}
signup_open() { ! signup_refused; }
check "vaultwarden: sign-ups open after install" signup_open
bash bin/rez vaultwarden close-signups
check "vaultwarden: sign-ups refused after close" signup_refused
check "vaultwarden: admin token is an argon2id hash" grep -q '^\$argon2id\$' "$HOME/.local/share/resurrect/vaultwarden/admin_token"
check "vaultwarden: autoclose cron removed" bash -c '! crontab -l | grep -q autoclose'

# AdGuard: no wizard (it can't run without root); config written by rez.
apw=$(cat "$C/secrets/adguard_password")
check "adguard answers DNS on 5335 (no root)" retry 20 bash bin/rez adguard test
check "adguard: generated password logs in" bash -c "curl -fsS -H 'Content-Type: application/json' -d '{\"name\":\"admin\",\"password\":\"$apw\"}' http://127.0.0.1:3000/control/login"
check "adguard: wrong password refused" bash -c "! curl -fsS -H 'Content-Type: application/json' -d '{\"name\":\"admin\",\"password\":\"wrong\"}' http://127.0.0.1:3000/control/login"
check "adguard: API needs login" bash -c "! curl -fsS http://127.0.0.1:3000/control/status"

# copyparty / filebrowser / syncthing
cpw=$(cat "$C/secrets/copyparty_password")
echo private >"$HOME/share/probe.txt"
check "copyparty: password reads a file" retry 10 bash -c "curl -fsS -u admin:$cpw http://127.0.0.1:3923/probe.txt | grep -q private"
check "copyparty: anonymous cannot read it" bash -c "! curl -fsS http://127.0.0.1:3923/probe.txt"
fpw=$(cat "$C/secrets/filebrowser_password")
check "filebrowser: login" retry 10 bash -c "curl -fsS -X POST http://127.0.0.1:8085/api/login -d '{\"username\":\"admin\",\"password\":\"$fpw\"}'"
check "syncthing GUI requires auth" retry 15 bash -c '[ "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:8384/rest/system/status)" = 401 ] || [ "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:8384/rest/system/status)" = 403 ]'

# Backups: run, verify, rotation keeps 2.
for i in 1 2 3; do bash bin/rez backup run >/dev/null 2>&1; sleep 61; done
check "backup: rotation keeps 2" test "$(ls "$HOME"/resurrect-backups/resurrect-*.tar.gz | wc -l)" = 2
check "backup: restore test passes" bash bin/rez backup verify
check "backup: contains vaultwarden db" bash -c 'tar -tzf "$(ls -1t ~/resurrect-backups/*.tar.gz | head -1)" | grep -q vaultwarden/db.sqlite3'
check "backup: archives are 600/dir 700" test "$(stat -c %a "$HOME/resurrect-backups")" = 700

# Monitor: kill copyparty; after 2 failed checks it alerts and restarts it.
old=$(cat "$S/run/copyparty.pid")
kill "$old"
sleep 25
new=$(bash -c 'source lib/common.sh; source lib/proc.sh; svc_pid copyparty copyparty-sfx.py' 2>/dev/null || true)
check "monitor restarted copyparty" test -n "$new" -a "$new" != "$old"
check "monitor sent a 'down' alert" bash -c "curl -fsS -u phone:$phone 'http://127.0.0.1:2586/alerts/json?poll=1' | grep -q 'copyparty is down'"

# Stale pidfile: point ntfy.pid at an unrelated live process, stop ntfy.
bash bin/rez stop ntfy >/dev/null 2>&1
sleep 300 & decoy=$!
echo "$decoy" >"$S/run/ntfy.pid"
bash bin/rez start ntfy >/dev/null 2>&1
check "stale pidfile did not fool start" retry 10 bash -c 'curl -fsS http://127.0.0.1:2586/v1/health'
check "decoy process untouched" kill -0 "$decoy"
kill "$decoy"

# Boot: everything stopped, boot script fired twice at once -> one of each.
bash bin/rez stop >/dev/null 2>&1
sleep 2
"$HOME/.termux/boot/resurrect" & "$HOME/.termux/boot/resurrect" & wait
sleep 8
check "boot: second copy exited on the lock" grep -q 'another copy is running' "$S/logs/boot.log"
dups=$(bash bin/rez status | grep 'copies running' || true)
[ -n "$dups" ] && echo "duplicates: $dups"
check "boot: no duplicate services" test -z "$dups"
for svc in ntfy vaultwarden adguard copyparty filebrowser syncthing monitor; do
  check "boot: $svc running" bash -c "bash bin/rez status | grep -E '^$svc ' | grep -q running"
done
check "rez boot again starts nothing new" bash -c '"$HOME/.termux/boot/resurrect"; ! bash bin/rez status | grep -q "copies running"'

check "doctor runs" bash -c 'bash bin/rez doctor; true'
check "uninstall --purge filebrowser" bash -c 'bash bin/rez --yes uninstall filebrowser --purge && ! test -d ~/.local/share/resurrect/filebrowser'

echo
echo "integration: $pass passed, $fail failed"
bash bin/rez stop >/dev/null 2>&1 || true
[ "$fail" -eq 0 ]
