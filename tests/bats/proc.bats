#!/usr/bin/env bats
# The "is it running" rules: never trust a pidfile, match /proc cmdline,
# never mistake a command that merely mentions a service for the service.

load test_helper

setup() {
  setup_sandbox
  load_libs
}

teardown() {
  kill_sandbox_procs
}

@test "proc_argv splits cmdline on NUL" {
  mkproc 100 1 /usr/bin/ntfy serve --config /x.yml
  run proc_argv 100
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = /usr/bin/ntfy ]
  [ "${lines[1]}" = serve ]
}

@test "proc_matches: direct binary, interpreter + script, proot-style path" {
  mkproc 100 1 /data/x/ntfy serve
  mkproc 101 1 python3 -m copyparty -c c.conf
  mkproc 102 1 /usr/local/bin/tailscaled --tun=userspace-networking
  proc_matches 100 ntfy serve
  proc_matches 101 copyparty
  proc_matches 102 tailscaled
}

@test "proc_matches rejects a shell command that only mentions the service" {
  mkproc 200 1 bash -c "ntfy serve --config x"
  mkproc 201 1 ssh phone "pgrep -f 'ntfy serve'"
  mkproc 202 1 grep ntfy
  mkproc 203 1 vim /etc/ntfy/server.yml
  ! proc_matches 200 ntfy serve
  ! proc_matches 201 ntfy serve
  ! proc_matches 202 ntfy
  ! proc_matches 203 ntfy
}

@test "proc_matches checks the argument regex" {
  mkproc 300 1 /bin/syncthing generate --home=x
  ! proc_matches 300 syncthing serve
}

@test "a supervisor loop is not mistaken for its child" {
  mkproc 400 1 bash "$REPO/lib/supervise.sh" tailscaled proot-distro login debian -- /usr/local/bin/tailscaled
  ! proc_matches 400 tailscaled
  proc_matches 400 supervise.sh "supervise\.sh tailscaled( |$)"
}

@test "svc_pid ignores and removes a stale pidfile whose PID was reused" {
  # After a reboot the pidfile says 500, but 500 is now an Android process.
  mkproc 500 1 com.android.localtransport
  echo 500 >"$REZ_RUN_DIR/ntfy.pid"
  run svc_pid ntfy ntfy serve
  [ "$status" -eq 1 ]
  [ ! -f "$REZ_RUN_DIR/ntfy.pid" ]
}

@test "svc_pid finds the real process when the pidfile is stale" {
  mkproc 500 1 com.android.localtransport
  mkproc 600 1 /data/x/ntfy serve
  echo 500 >"$REZ_RUN_DIR/ntfy.pid"
  run svc_pid ntfy ntfy serve
  [ "$status" -eq 0 ]
  [ "$output" = 600 ]
  [ "$(cat "$REZ_RUN_DIR/ntfy.pid")" = 600 ]
}

@test "svc_pid trusts a pidfile only when cmdline matches" {
  mkproc 700 1 /data/x/vaultwarden
  echo 700 >"$REZ_RUN_DIR/vaultwarden.pid"
  run svc_pid vaultwarden vaultwarden
  [ "$output" = 700 ]
}

@test "proc_find never finds the process that is asking (the pgrep -f trap)" {
  # A script whose own command line looks exactly like the service.
  export REZ_PROC=/proc
  printf '#!/usr/bin/env bash\nsource %s/lib/common.sh\nsource %s/lib/proc.sh\nproc_find ntfy serve\n' "$REPO" "$REPO" >"$T/ntfy"
  chmod +x "$T/ntfy"
  run "$T/ntfy" serve
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "svc_status_line flags duplicate copies" {
  mkproc 800 1 /data/x/ntfy serve
  mkproc 801 1 /data/x/ntfy serve
  run svc_status_line ntfy ntfy serve
  [[ "$output" == *"2 copies running"* ]]
}

@test "svc_start does not start a second copy" {
  mkproc 900 1 /data/x/ntfy serve
  run svc_start ntfy ntfy serve -- /bin/false
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running (pid 900)"* ]]
}

@test "with_lock: second holder gets 75 and does not run" {
  lock=$T/l.lock
  with_lock "$lock" sleep 2 3>&- &
  holder=$!
  sleep 0.5
  run with_lock "$lock" touch "$T/ran"
  [ "$status" -eq 75 ]
  [ ! -e "$T/ran" ]
  wait "$holder"
}

@test "real process lifecycle: start, detect, stop (uses the real /proc)" {
  export REZ_PROC=/proc
  make_dummy rezdummy
  svc_start dummy rezdummy "" -- "$T/rezdummy" 3>&-
  svc_running dummy rezdummy
  svc_stop dummy rezdummy
  ! svc_running dummy rezdummy
}

@test "svc_stop stops every running copy, not just one (uses the real /proc)" {
  export REZ_PROC=/proc
  make_dummy rezdummy
  svc_start dummy rezdummy "" -- "$T/rezdummy" 3>&-
  # A second copy, as a leftover second boot script would start it.
  "$T/rezdummy" 3>&- >/dev/null 2>&1 </dev/null &
  for _ in $(seq 1 20); do
    [ "$(proc_find rezdummy | wc -l)" -eq 2 ] && break
    sleep 0.25
  done
  [ "$(proc_find rezdummy | wc -l)" -eq 2 ]
  run svc_stop dummy rezdummy
  [ "$status" -eq 0 ]
  [[ "$output" == *"dummy stopped (2 copies)"* ]]
  [ -z "$(proc_find rezdummy)" ]
  ! svc_running dummy rezdummy
}

@test "supervised process is restarted after a crash" {
  export REZ_PROC=/proc
  make_dummy rezcrash
  SVC_SUPERVISE=1 svc_start crashy rezcrash "" -- "$T/rezcrash" 3>&-
  first=$(svc_pid crashy rezcrash)
  kill "$first"
  for _ in $(seq 1 20); do
    sleep 0.5
    p=$(svc_pid crashy rezcrash || true)
    [ -n "$p" ] && [ "$p" != "$first" ] && break
  done
  [ -n "$p" ] && [ "$p" != "$first" ]
  svc_stop crashy rezcrash
  ! svc_running crashy rezcrash
  [ -z "$(proc_find supervise.sh 'supervise\.sh crashy( |$)')" ]
}
