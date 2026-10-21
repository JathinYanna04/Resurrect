#!/usr/bin/env bash
# supervise.sh NAME CMD...: keep CMD running.
#
# Restarts CMD whenever it exits. Waits 5 s, doubling up to 5 min while it
# keeps crashing quickly; a run longer than 10 min resets the wait. Sends an
# ntfy alert on the 1st and every 5th consecutive crash. Exits when
# $REZ_RUN_DIR/NAME.stop exists (svc_stop creates it) or on SIGTERM.
set -u
name=$1; shift
REZ_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$REZ_ROOT/lib/common.sh"
# shellcheck source=lib/notify.sh
source "$REZ_ROOT/lib/notify.sh"

stopfile="$REZ_RUN_DIR/$name.stop"
wait_s=5 crashes=0 child=''
trap '[[ -n "$child" ]] && kill "$child" 2>/dev/null; exit 0' TERM INT HUP

while :; do
  [[ -e "$stopfile" ]] && exit 0
  start=$(date +%s)
  "$@" &
  child=$!
  echo "$child" >"$REZ_RUN_DIR/$name.pid"
  wait "$child"
  rc=$?
  child=''
  [[ -e "$stopfile" ]] && exit 0
  ran=$(( $(date +%s) - start ))
  if (( ran >= 600 )); then wait_s=5 crashes=0; fi
  crashes=$((crashes + 1))
  echo "$(date '+%F %T') supervise: $name exited (code $rc) after ${ran}s, restart in ${wait_s}s"
  if (( crashes == 1 || crashes % 5 == 0 )); then
    notify_send "$name restarted" "$name exited (code $rc) after ${ran}s; restart #$crashes in ${wait_s}s." 4 warning &
  fi
  sleep "$wait_s"
  (( ran < 60 )) && wait_s=$(( wait_s * 2 > 300 ? 300 : wait_s * 2 ))
done
