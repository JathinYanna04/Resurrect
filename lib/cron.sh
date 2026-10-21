# shellcheck shell=bash
# The resurrect block in the user's crontab. Lines outside the block are
# never touched. Each module can print cron lines from mod_cron.

[[ -n "${_REZ_CRON_LOADED:-}" ]] && return 0
_REZ_CRON_LOADED=1

REZ_CRON_BEGIN="# >>> resurrect (managed by rez, edits here are overwritten) >>>"
REZ_CRON_END="# <<< resurrect <<<"

# cron_strip: crontab on stdin, our block removed, on stdout.
cron_strip() {
  awk -v b="$REZ_CRON_BEGIN" -v e="$REZ_CRON_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }'
}

# cron_install_block: replace the block with the lines on stdin (empty
# input removes the block).
cron_install_block() {
  local lines current new
  lines=$(cat)
  current=$(crontab -l 2>/dev/null || true)
  new=$(cron_strip <<<"$current")
  if [[ -n "$lines" ]]; then
    new+=$'\n'"$REZ_CRON_BEGIN"$'\n'"$lines"$'\n'"$REZ_CRON_END"
  fi
  new=$(sed '/./,$!d' <<<"$new")
  if [[ "$REZ_DRY_RUN" == 1 ]]; then
    printf '[dry-run] crontab would become:\n%s\n' "$new" >&2
    return 0
  fi
  printf '%s\n' "$new" | crontab -
}

# rez_cmd: how cron and the boot script call rez. Full paths only: neither
# has a useful PATH, and termux-exec (which fixes #! lines) is not loaded.
rez_cmd() { printf '%s/bin/bash %s/bin/rez' "$PREFIX" "$REZ_ROOT"; }
