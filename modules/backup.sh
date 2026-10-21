# shellcheck shell=bash
# backup: nightly archive of every module's data, keep N, weekly restore test.
#
# Each module decides what matters (mod_backup) and how to check a restored
# copy (mod_restore_check). SQLite databases are copied with `.backup`, which
# is consistent while the service runs. Archives contain secrets, so the
# folder is mode 700. Copy them OFF the phone: extras/laptop/pull-backups.sh.

MOD_NAME=backup
MOD_DESC="Nightly backups, keep N, weekly restore test, optional pull to a computer"
MOD_DEPENDS="base"
MOD_SERVICE=0
MOD_DISK_EST_MB=50
MOD_TESTED="termux-docker: run, rotation, restore test, archive contents, folder mode. Cron timing: real device only"

_dir() { local d; d=$(cfg_get backup.dir "$HOME/resurrect-backups"); echo "${d/#\~/$HOME}"; }
_keep() { cfg_get backup.keep 7; }
_stamp() { echo "$REZ_STATE_DIR/$1"; }

mod_configure() {
  cfg_set backup.keep "$(cfg_get backup.keep "$(ui_input "Backups" "How many nightly backups to keep" 7)")"
  local pull
  pull=$(cfg_get backup.expect_pull "")
  if [[ -z "$pull" ]]; then
    pull=no
    ui_yesno "Backups" "A backup that only lives on the phone dies with the phone.
Will you copy backups to a computer with extras/laptop/pull-backups.sh? (You get an alert if none was pulled for 3 days.)" yes && pull=yes
  fi
  cfg_set backup.expect_pull "$pull"
}

mod_install() {
  ensure_dir 700 "$(_dir)"
  [[ -n "$(cfg_get backup.installed_at "")" ]] || cfg_set backup.installed_at "$(date +%s)"
}

mod_cron() {
  echo "30 3 * * * $(rez_cmd) backup run >>$REZ_LOG_DIR/backup.log 2>&1"
  echo "15 5 * * 0 $(rez_cmd) backup verify >>$REZ_LOG_DIR/backup.log 2>&1"
}

# Newest first. Names never contain spaces (resurrect-DATE_TIME.tar.gz).
_archives() { ls -1t "$(_dir)"/resurrect-*.tar.gz 2>/dev/null || true; }
_latest() { _archives | head -n1; }

backup_run() {
  local out work name m fail=0 failed=''
  out=$(_dir)
  ensure_dir 700 "$out"
  umask 077
  work=$(mktemp -d "$REZ_STATE_DIR/backup.XXXXXX")
  name="resurrect-$(date +%F_%H%M).tar.gz"
  for m in $(modules_enabled); do
    module_has "$m" backup || continue
    if module_call "$m" backup "$work/$m"; then
      debug "backed up $m"
    else
      fail=1 failed+="$m "
      err "backup of $m failed"
    fi
  done
  {
    echo "resurrect $REZ_VERSION backup"
    echo "created: $(date '+%F %T %z')"
    echo "modules: $(modules_enabled | tr '\n' ' ')"
    [[ -n "$failed" ]] && echo "FAILED: $failed"
  } >"$work/MANIFEST"
  if tar -C "$work" -czf "$out/$name.part" . && mv "$out/$name.part" "$out/$name"; then
    (cd "$out" && sha256sum "$name" >"$name.sha256")
  else
    fail=1 failed+="archive "
    rm -f "$out/$name.part"
  fi
  rm -rf "$work"
  # Keep the newest N archives.
  _archives | tail -n +"$(( $(_keep) + 1 ))" | while read -r old; do rm -f "$old" "$old.sha256"; done
  if ((fail)); then
    notify_send "Backup failed" "Problems with: $failed. Log: $REZ_LOG_DIR/backup.log" 4 warning
    return 1
  fi
  date +%s >"$(_stamp last-backup)"
  ok "backup written: $out/$name ($(du -h "$out/$name" | cut -f1))"
}

# backup_verify [FILE]: checksum, extract to a scratch folder, run each
# module's restore check. Touches nothing live.
backup_verify() {
  local f=${1:-$(_latest)} work m d fail=0 report=''
  [[ -n "$f" && -f "$f" ]] || die "no backup found"
  if [[ -f "$f.sha256" ]]; then
    (cd "$(dirname "$f")" && sha256sum -c --quiet "$(basename "$f").sha256") || { notify_send "Backup verify failed" "Checksum mismatch: $f" 4 warning; die "checksum mismatch: $f"; }
  fi
  work=$(mktemp -d "$REZ_STATE_DIR/verify.XXXXXX")
  tar -xzf "$f" -C "$work" || { rm -rf "$work"; die "cannot extract $f"; }
  for d in "$work"/*/; do
    m=$(basename "$d")
    module_exists "$m" || continue
    local out
    if out=$(module_call "$m" restore_check "$d" 2>&1); then
      report+="  $m: ok${out:+ ($out)}"$'\n'
    else
      fail=1 report+="  $m: FAILED ${out}"$'\n'
    fi
  done
  rm -rf "$work"
  printf 'verify %s\n%s' "$(basename "$f")" "$report"
  if ((fail)); then
    notify_send "Backup restore test failed" "$(basename "$f"):
$report" 4 warning
    return 1
  fi
  date +%s >"$(_stamp last-verify)"
  ok "restore test passed"
}

_age_h() { local t; t=$(cat "$1" 2>/dev/null) || { echo -1; return; }; echo $(( ($(date +%s) - t) / 3600 )); }

mod_status() {
  local n last
  n=$(_archives | wc -l)
  last=$(_age_h "$(_stamp last-backup)")
  printf '%-14s %s backups kept, last %s, verified %s, pulled %s\n' backup "$n" \
    "$( ((last >= 0)) && echo "${last}h ago" || echo never)" \
    "$(a=$(_age_h "$(_stamp last-verify)"); ((a >= 0)) && echo "${a}h ago" || echo never)" \
    "$(a=$(_age_h "$(_stamp last-backup-pull)"); ((a >= 0)) && echo "${a}h ago" || echo never)"
}

mod_health() {
  local since age
  since=$(( ($(date +%s) - $(cfg_get backup.installed_at "$(date +%s)")) / 3600 ))
  age=$(_age_h "$(_stamp last-backup)")
  if (( since > 36 && (age < 0 || age > 36) )); then echo "no successful backup in 36 h"; return 1; fi
  if [[ "$(cfg_get backup.expect_pull no)" == yes ]] && ((since > 72)); then
    age=$(_age_h "$(_stamp last-backup-pull)")
    if ((age < 0 || age > 72)); then echo "backups have not left the phone for 3 days"; return 1; fi
  fi
  return 0
}

mod_uninstall() { info "backups in $(_dir) were left in place"; }

mod_info() { printf 'Backups:    %s nightly at 03:30, keep %s (rez backup list)\n' "$(_dir)" "$(_keep)"; }

mod_cli() {
  local cmd=${1:-}; (($#)) && shift
  case "$cmd" in
    run) with_lock "$REZ_STATE_DIR/backup.lock" backup_run || { (($? == 75)) && warn "a backup is already running"; return 1; } ;;
    verify) backup_verify "$@" ;;
    list) ls -lh "$(_dir)"/resurrect-*.tar.gz 2>/dev/null || echo "no backups yet" ;;
    extract)
      [[ $# -eq 2 ]] || die "usage: rez backup extract FILE DIR"
      mkdir -p "$2"; tar -xzf "$1" -C "$2"; ok "extracted to $2 (restore steps: docs/backups.md)" ;;
    mark-pulled) date +%s >"$(_stamp last-backup-pull)" ;;
    *) die "usage: rez backup run|list|verify [FILE]|extract FILE DIR" ;;
  esac
}
