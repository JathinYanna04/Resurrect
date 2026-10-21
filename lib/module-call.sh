#!/usr/bin/env bash
# module-call.sh NAME FUNC [ARGS...]: run one module action in a fresh bash.
#
# Why a new process and not a subshell: callers often test the result
# (`if ! module_call x install`), and bash ignores `set -e` for everything
# run inside such a condition, subshells included. A failing install step
# would then be skipped silently. A new process always runs with -e.
# State comes from the environment (REZ_*, DEV_*, exported by the caller).
set -Eeuo pipefail
REZ_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REZ_ROOT
for _l in common config proc ui detect fetch proot cron notify modules setup device doctor; do
  # shellcheck source=/dev/null
  source "$REZ_ROOT/lib/$_l.sh"
done
unset _l
trap 'err "${MOD_NAME:-module}: failed at ${BASH_SOURCE[0]##*/}:$LINENO: $BASH_COMMAND"' ERR
name=$1 fn=$2
shift 2
module_load "$name"
declare -F "mod_$fn" >/dev/null || exit 0
"mod_$fn" "$@"
