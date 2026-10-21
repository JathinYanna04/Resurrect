# shellcheck shell=bash
# Shared helpers: paths, logging, dry-run, small utilities.
# Sourced by bin/rez, install.sh and every module. Never executed directly.

[[ -n "${_REZ_COMMON_LOADED:-}" ]] && return 0
_REZ_COMMON_LOADED=1

REZ_VERSION="0.1.0"

# --- Paths -------------------------------------------------------------------
# Everything is overridable through the environment, which is how tests run
# the code outside Termux.
: "${PREFIX:=/data/data/com.termux/files/usr}"
: "${REZ_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${REZ_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/resurrect}"
: "${REZ_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/resurrect}"
: "${REZ_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/resurrect}"
: "${REZ_LOG_DIR:=$REZ_STATE_DIR/logs}"
: "${REZ_RUN_DIR:=$REZ_STATE_DIR/run}"
: "${REZ_PROC:=/proc}"
: "${REZ_BOOT_DIR:=$HOME/.termux/boot}"
export PREFIX REZ_ROOT REZ_CONFIG_DIR REZ_STATE_DIR REZ_DATA_DIR REZ_LOG_DIR REZ_RUN_DIR REZ_PROC

: "${REZ_DRY_RUN:=0}"
: "${REZ_NONINTERACTIVE:=0}"
: "${REZ_ASSUME_YES:=0}"
: "${REZ_DEBUG:=0}"

# --- Logging -----------------------------------------------------------------
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _c_red=$'\e[31m' _c_grn=$'\e[32m' _c_ylw=$'\e[33m' _c_blu=$'\e[34m' _c_dim=$'\e[2m' _c_off=$'\e[0m'
else
  _c_red='' _c_grn='' _c_ylw='' _c_blu='' _c_dim='' _c_off=''
fi

_log_file() {
  [[ -d "$REZ_LOG_DIR" ]] || return 0
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$REZ_LOG_DIR/rez.log" 2>/dev/null || true
}
info()  { printf '%s==>%s %s\n' "$_c_blu" "$_c_off" "$*" >&2; _log_file "INFO $*"; }
ok()    { printf '%s ok%s %s\n' "$_c_grn" "$_c_off" "$*" >&2; _log_file "OK   $*"; }
warn()  { printf '%swarn%s %s\n' "$_c_ylw" "$_c_off" "$*" >&2; _log_file "WARN $*"; }
err()   { printf '%serror%s %s\n' "$_c_red" "$_c_off" "$*" >&2; _log_file "ERR  $*"; }
debug() { [[ "$REZ_DEBUG" == 1 ]] && printf '%sdebug %s%s\n' "$_c_dim" "$*" "$_c_off" >&2; return 0; }
die()   { err "$*"; exit 1; }

# run_cmd CMD...: execute, or only print it in dry-run mode.
# (Not "run": that name belongs to bats in the test suite.)
run_cmd() {
  if [[ "$REZ_DRY_RUN" == 1 ]]; then
    printf '%s[dry-run]%s %s\n' "$_c_dim" "$_c_off" "$*" >&2
    return 0
  fi
  debug "run: $*"
  "$@"
}

# --- Environment checks ------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" || -d /data/data/com.termux/files/usr ]] && [[ "$PREFIX" == */com.termux/* ]]
}

require_cmd() {
  local c
  for c in "$@"; do have "$c" || die "required command not found: $c"; done
}

# ensure_dir MODE DIR...
ensure_dir() {
  local mode=$1 d; shift
  for d in "$@"; do
    [[ -d "$d" ]] || run_cmd mkdir -p "$d"
    run_cmd chmod "$mode" "$d"
  done
}

rez_init_dirs() {
  ensure_dir 700 "$REZ_CONFIG_DIR" "$REZ_CONFIG_DIR/secrets" "$REZ_STATE_DIR" "$REZ_RUN_DIR"
  ensure_dir 755 "$REZ_DATA_DIR" "$REZ_LOG_DIR"
}

# --- Root --------------------------------------------------------------------
# Root is optional everywhere. These helpers never trigger a Magisk prompt on
# their own; callers ask first (see detect_root).
REZ_HAS_ROOT="${REZ_HAS_ROOT:-unknown}"

as_root() {
  [[ "$REZ_HAS_ROOT" == yes ]] || die "this action needs root, which is not available"
  run_cmd su -c "$*"
}

# --- Misc --------------------------------------------------------------------
# csv_has LIST ITEM: is ITEM in the comma/space separated LIST?
csv_has() {
  local list=",${1//[[:space:]]/,}," item=$2
  [[ "$list" == *",$item,"* ]]
}

# rand_token [LEN]: URL-safe random string.
rand_token() {
  local len=${1:-32} out=''
  while ((${#out} < len)); do
    out+=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
  done
  printf '%s' "${out:0:len}"
}

# atomic_write FILE MODE: write stdin to FILE via a temp file in the same dir.
atomic_write() {
  local f=$1 mode=${2:-600} tmp
  if [[ "$REZ_DRY_RUN" == 1 ]]; then
    printf '%s[dry-run]%s write %s\n' "$_c_dim" "$_c_off" "$f" >&2
    cat >/dev/null
    return 0
  fi
  tmp=$(mktemp "${f}.XXXXXX")
  cat >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$f"
}

# mem_kb FIELD: a /proc/meminfo field in kB (MemTotal, MemAvailable, ...).
mem_kb() {
  awk -v k="$1:" '$1 == k { print $2; exit }' "$REZ_PROC/meminfo" 2>/dev/null || true
}

# mem_available_mb: what can be used without swapping. Never use `free`:
# Android's toybox free reports page cache as used and looks near-empty.
mem_available_mb() {
  local kb
  kb=$(mem_kb MemAvailable)
  [[ -n "$kb" ]] || kb=$(mem_kb MemFree)
  echo $(( ${kb:-0} / 1024 ))
}

mem_total_mb() {
  local kb
  kb=$(mem_kb MemTotal)
  echo $(( ${kb:-0} / 1024 ))
}

# free_mb DIR: free space on the filesystem holding DIR.
free_mb() {
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }' || true
}

# TLS_ENV: where Linux Go/musl binaries find CA certificates on Android.
# Termux's bundle first (kept current by pkg); Android's store as fallback
# (on Android 14+ it can be stale, since updates go to an APEX).
TLS_ENV=("SSL_CERT_FILE=$PREFIX/etc/tls/cert.pem" "SSL_CERT_DIR=/system/etc/security/cacerts")

# port_open HOST PORT: TCP connect test, 3 s timeout.
port_open() {
  timeout 3 bash -c ">/dev/tcp/$1/$2" 2>/dev/null
}
