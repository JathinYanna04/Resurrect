# shellcheck shell=bash
# Process management that survives Android's habits.
#
# Rules (each one caused a real outage somewhere):
#  - A pidfile is only a hint. Android reuses PIDs after a reboot, so a stale
#    pidfile can point at an unrelated live process. Every check reads
#    /proc/<pid>/cmdline and compares it with what the service should be.
#  - Never trust `kill -0 <pid>` on its own for the same reason.
#  - `pgrep -f` matches the command line of whoever runs it (an ssh session
#    that mentions a service name counts as "running"). The scanner here
#    compares argv elements exactly and skips itself and its ancestors.
#  - Start only if not already running: no duplicates, ever.

[[ -n "${_REZ_PROC_LOADED:-}" ]] && return 0
_REZ_PROC_LOADED=1

# Programs whose argv can mention a service without being it.
_REZ_PROC_IGNORE=" ssh sshd grep egrep pgrep pkill sudo su tsu less more tail head vi vim nvim nano cat man rez watch "

# proc_argv PID: argv elements, one per line. Fails if the process is gone.
proc_argv() {
  local f="$REZ_PROC/$1/cmdline"
  [[ -r "$f" ]] || return 1
  local data
  data=$(tr '\0' '\n' <"$f" 2>/dev/null) || return 1
  [[ -n "$data" ]] || return 1
  printf '%s\n' "$data"
}

# proc_matches PID EXE [ARGS_REGEX]
# True if one of argv[0..2] has basename EXE (so "bash script.sh", "python3 -I x.py"
# and proot's loader work) and the whole command line matches ARGS_REGEX.
proc_matches() {
  local pid=$1 exe=$2 args=${3:-} argv first i=0 line hit=0
  argv=$(proc_argv "$pid") || return 1
  first=$(head -n1 <<<"$argv")
  first=${first##*/}
  [[ "$_REZ_PROC_IGNORE" == *" $first "* && "$first" != "$exe" ]] && return 1
  # A supervisor loop's argv names its child; it is not the child itself.
  if [[ "$exe" != supervise.sh ]]; then
    line=$(sed -n 2p <<<"$argv")
    [[ "${line##*/}" == supervise.sh ]] && return 1
  fi
  while IFS= read -r line && ((i < 3)); do
    if [[ "${line##*/}" == "$exe" ]]; then hit=1; break; fi
    i=$((i + 1))
  done <<<"$argv"
  ((hit)) || return 1
  [[ -z "$args" ]] && return 0
  grep -Eq -- "$args" <<<"${argv//$'\n'/ }"
}

# _proc_ancestors: our own PID and every ancestor's, space separated.
_proc_ancestors() {
  local pid=${BASHPID:-$$} out=" " ppid
  while [[ -n "$pid" && "$pid" != 0 ]]; do
    out+="$pid "
    ppid=$(awk '/^PPid:/ { print $2 }' "$REZ_PROC/$pid/status" 2>/dev/null)
    [[ "$ppid" == "$pid" ]] && break
    pid=$ppid
  done
  printf '%s' "$out"
}

# proc_find EXE [ARGS_REGEX]: print PIDs of matching processes, oldest first.
proc_find() {
  local exe=$1 args=${2:-} skip d pid
  skip=$(_proc_ancestors)
  for d in "$REZ_PROC"/[0-9]*; do
    pid=${d##*/}
    [[ "$skip" == *" $pid "* ]] && continue
    proc_matches "$pid" "$exe" "$args" && echo "$pid"
  done | sort -n
}

# --- Services ----------------------------------------------------------------
# A service is identified by NAME and matched by EXE + ARGS_REGEX. Modules
# call these with their own values; the pidfile only saves a /proc scan.

_svc_pidfile() { echo "$REZ_RUN_DIR/$1.pid"; }

# svc_pid NAME EXE [ARGS_REGEX]: print the live PID or fail.
svc_pid() {
  local name=$1 exe=$2 args=${3:-} pf pid
  pf=$(_svc_pidfile "$name")
  if [[ -r "$pf" ]]; then
    pid=$(<"$pf")
    if [[ "$pid" =~ ^[0-9]+$ ]] && proc_matches "$pid" "$exe" "$args"; then
      echo "$pid"
      return 0
    fi
    debug "stale pidfile for $name (pid $pid), removing"
    rm -f "$pf"
  fi
  pid=$(proc_find "$exe" "$args" | head -n1)
  [[ -n "$pid" ]] || return 1
  [[ -d "$REZ_RUN_DIR" ]] && echo "$pid" >"$pf"
  echo "$pid"
}

svc_running() { svc_pid "$@" >/dev/null; }

# svc_start NAME EXE ARGS_REGEX -- CMD...
# Start CMD detached unless already running. Logs to $REZ_LOG_DIR/NAME.log.
# Set SVC_ENV=("K=V" ...) to pass environment. Set SVC_SUPERVISE=1 to wrap
# CMD in lib/supervise.sh (restart with backoff, ntfy alert on crash loops).
svc_start() {
  local name=$1 exe=$2 args=$3; shift 3
  [[ "$1" == "--" ]] && shift
  local pid log="$REZ_LOG_DIR/$name.log"
  if pid=$(svc_pid "$name" "$exe" "$args"); then
    ok "$name already running (pid $pid)"
    return 0
  fi
  if [[ "$REZ_DRY_RUN" == 1 ]]; then
    run "$@"
    return 0
  fi
  mkdir -p "$REZ_LOG_DIR" "$REZ_RUN_DIR"
  local -a cmd=("$@")
  if [[ "${SVC_SUPERVISE:-0}" == 1 ]]; then
    rm -f "$REZ_RUN_DIR/$name.stop"
    cmd=(bash "$REZ_ROOT/lib/supervise.sh" "$name" "$@")
  fi
  # setsid: survive the session that started it (ssh logout, Termux tab close).
  env "${SVC_ENV[@]}" setsid nohup "${cmd[@]}" >>"$log" 2>&1 </dev/null &
  local i
  for i in 1 2 3 4 5 6; do
    sleep 1
    if pid=$(svc_pid "$name" "$exe" "$args"); then
      ok "$name started (pid $pid)"
      return 0
    fi
  done
  err "$name did not stay up; last log lines:"
  tail -n 15 "$log" >&2 2>/dev/null || true
  return 1
}

# svc_stop NAME EXE [ARGS_REGEX]: stop the service (and its supervisor loop).
svc_stop() {
  local name=$1 exe=$2 args=${3:-} pid loop i
  touch "$REZ_RUN_DIR/$name.stop" 2>/dev/null || true
  for loop in $(proc_find supervise.sh "supervise\.sh $name( |$)"); do
    run kill "$loop" 2>/dev/null || true
  done
  if ! pid=$(svc_pid "$name" "$exe" "$args"); then
    ok "$name not running"
    rm -f "$(_svc_pidfile "$name")"
    return 0
  fi
  run kill "$pid" 2>/dev/null || true
  [[ "$REZ_DRY_RUN" == 1 ]] && return 0
  for i in $(seq 1 15); do
    proc_matches "$pid" "$exe" "$args" || break
    sleep 1
  done
  if proc_matches "$pid" "$exe" "$args"; then
    warn "$name ignored SIGTERM, sending SIGKILL"
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$(_svc_pidfile "$name")"
  ok "$name stopped"
}

# svc_status_line NAME EXE [ARGS_REGEX] [EXTRA]: one line for `rez status`.
svc_status_line() {
  local name=$1 exe=$2 args=${3:-} extra=${4:-} pid
  if pid=$(svc_pid "$name" "$exe" "$args"); then
    local n
    n=$(proc_find "$exe" "$args" | wc -l)
    ((n > 1)) && extra="${_c_ylw}$n copies running!${_c_off} $extra"
    printf '%-14s %srunning%s  pid %-7s %s\n' "$name" "$_c_grn" "$_c_off" "$pid" "$extra"
    return 0
  fi
  printf '%-14s %sstopped%s  %-11s %s\n' "$name" "$_c_red" "$_c_off" "" "$extra"
  return 1
}

# with_lock LOCKFILE CMD...: run CMD only if nobody else holds LOCKFILE.
# Returns 75 (EX_TEMPFAIL) without running CMD when the lock is taken.
with_lock() {
  local lock=$1; shift
  mkdir -p "$(dirname "$lock")"
  if have flock; then
    (
      flock -n 9 || exit 75
      "$@"
    ) 9>"$lock"
  else
    # mkdir is atomic; good enough where util-linux is missing.
    if mkdir "$lock.d" 2>/dev/null; then
      trap 'rmdir "$lock.d" 2>/dev/null' RETURN
      "$@"
    else
      return 75
    fi
  fi
}
