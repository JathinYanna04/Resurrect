# shellcheck shell=bash
# Shared setup for the bats suite. Every test gets its own sandbox: HOME,
# PREFIX, config/state dirs and a fake /proc, so nothing touches the machine
# running the tests (a laptop, CI, or the termux-docker image).

REPO=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)

setup_sandbox() {
  T=$BATS_TEST_TMPDIR
  export HOME=$T/home PREFIX=$T/prefix
  mkdir -p "$HOME" "$PREFIX/bin" "$T/proc" "$T/storage"
  export REZ_ROOT=$REPO
  export REZ_CONFIG_DIR=$HOME/.config/resurrect REZ_STATE_DIR=$HOME/.local/state/resurrect
  export REZ_DATA_DIR=$HOME/.local/share/resurrect REZ_LOG_DIR=$HOME/.local/state/resurrect/logs
  export REZ_RUN_DIR=$HOME/.local/state/resurrect/run REZ_BOOT_DIR=$HOME/.termux/boot
  export REZ_CONFIG_FILE=$REZ_CONFIG_DIR/resurrect.conf
  export REZ_PROC=$T/proc REZ_STORAGE_ROOT=$T/storage
  export REZ_GETPROP=$REPO/tests/mocks/getprop
  export REZ_ALLOW_NON_TERMUX=1 REZ_NONINTERACTIVE=1 NO_COLOR=1 REZ_UI=none
  mkdir -p "$REZ_CONFIG_DIR" "$REZ_RUN_DIR" "$REZ_LOG_DIR"
  meminfo 2878000 1440000
  # A fake crontab that stores its table in a file.
  cat >"$PREFIX/bin/crontab" <<'EOF'
#!/bin/sh
f="$HOME/.crontab"
case "$1" in
  -l) [ -f "$f" ] && cat "$f" || { echo "no crontab for user" >&2; exit 1; } ;;
  -) cat > "$f" ;;
  *) echo "fake crontab: unsupported $*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$PREFIX/bin/crontab"
  export PATH=$PREFIX/bin:$PATH
}

# meminfo TOTAL_KB AVAILABLE_KB: write the fake /proc/meminfo.
meminfo() {
  printf 'MemTotal:       %s kB\nMemFree:          100000 kB\nMemAvailable:   %s kB\n' "$1" "$2" >"$REZ_PROC/meminfo"
}

# mkproc PID PPID ARGV...: add a process to the fake /proc.
mkproc() {
  local pid=$1 ppid=$2; shift 2
  mkdir -p "$REZ_PROC/$pid"
  printf '%s\0' "$@" >"$REZ_PROC/$pid/cmdline"
  printf 'Name:\t%s\nPPid:\t%s\n' "${1##*/}" "$ppid" >"$REZ_PROC/$pid/status"
}

# Source the libraries into the test shell (what bin/rez does).
load_libs() {
  local l
  for l in common config proc ui detect fetch proot cron notify modules setup device doctor; do
    # shellcheck source=/dev/null
    source "$REPO/lib/$l.sh"
  done
}

rez() { bash "$REPO/bin/rez" "$@"; }

# make_dummy NAME: a long-running fake service whose name shows up in its
# /proc cmdline on every platform (a copied `sleep` may report itself as
# "sleep", e.g. Termux's coreutils).
make_dummy() {
  printf '#!/usr/bin/env python3\nimport time\ntime.sleep(300)\n' >"$T/$1"
  chmod +x "$T/$1"
}

# kill_sandbox_procs: stop anything a test started (supervisor loops first),
# so no stray process outlives the test and keeps bats waiting.
kill_sandbox_procs() {
  local d pid
  touch "$REZ_RUN_DIR"/crashy.stop "$REZ_RUN_DIR"/dummy.stop 2>/dev/null || true
  for d in /proc/[0-9]*; do
    pid=${d##*/}
    [[ "$pid" == "$$" || "$pid" == "${BASHPID:-}" ]] && continue
    if tr '\0' ' ' 2>/dev/null <"$d/cmdline" | grep -qF "$BATS_TEST_TMPDIR"; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
