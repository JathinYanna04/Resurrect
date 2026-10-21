# shellcheck shell=bash
# Terminal UI: `dialog` when available, numbered prompts otherwise, and
# defaults (or a clean error) in non-interactive mode.

[[ -n "${_REZ_UI_LOADED:-}" ]] && return 0
_REZ_UI_LOADED=1

: "${REZ_UI:=}"
: "${REZ_TTY:=/dev/tty}"

ui_mode() {
  if [[ -n "$REZ_UI" ]]; then echo "$REZ_UI"; return; fi
  if [[ "$REZ_NONINTERACTIVE" == 1 ]] || ! { : >"$REZ_TTY"; } 2>/dev/null; then echo none
  elif have dialog && [[ -t 1 ]]; then echo dialog
  else echo plain
  fi
}

_dlg() { dialog --stdout --backtitle "resurrect $REZ_VERSION — raise your dead phone as a homelab" "$@" <"$REZ_TTY"; }

_tty_read() {
  local __v
  IFS= read -r __v <"$REZ_TTY" || __v=''
  printf '%s' "$__v"
}

# ui_msg TITLE TEXT
ui_msg() {
  case $(ui_mode) in
    dialog) _dlg --title "$1" --msgbox "$2" 0 0 >/dev/null || true ;;
    plain) printf '\n== %s ==\n%s\n\nPress Enter to continue. ' "$1" "$2" >"$REZ_TTY"; _tty_read >/dev/null ;;
    none) printf '== %s ==\n%s\n' "$1" "$2" >&2 ;;
  esac
}

# ui_yesno TITLE TEXT [DEFAULT yes|no]: 0 = yes.
ui_yesno() {
  local title=$1 text=$2 def=${3:-no} a
  case $(ui_mode) in
    dialog)
      local -a extra=()
      [[ "$def" == no ]] && extra=(--defaultno)
      _dlg --title "$title" "${extra[@]}" --yesno "$text" 0 0 >/dev/null
      ;;
    plain)
      printf '\n== %s ==\n%s\n' "$title" "$text" >"$REZ_TTY"
      while :; do
        printf '[%s] ' "$([[ $def == yes ]] && echo 'Y/n' || echo 'y/N')" >"$REZ_TTY"
        a=$(_tty_read)
        case "${a,,}" in
          '') [[ "$def" == yes ]]; return ;;
          y | yes) return 0 ;;
          n | no) return 1 ;;
        esac
      done
      ;;
    none)
      [[ "$REZ_ASSUME_YES" == 1 ]] && return 0
      [[ "$def" == yes ]]
      ;;
  esac
}

# ui_input TITLE TEXT DEFAULT [required]: prints the answer.
ui_input() {
  local title=$1 text=$2 def=${3:-} req=${4:-} a
  case $(ui_mode) in
    dialog) a=$(_dlg --title "$title" --inputbox "$text" 0 0 "$def") || return 1 ;;
    plain)
      printf '\n%s\n%s [%s]: ' "$title" "$text" "$def" >"$REZ_TTY"
      a=$(_tty_read); a=${a:-$def}
      ;;
    none) a=$def ;;
  esac
  if [[ -z "$a" && "$req" == required ]]; then
    [[ $(ui_mode) == none ]] && die "$title: no value given (set it with --config or a flag)"
    ui_input "$@"
    return
  fi
  printf '%s' "$a"
}

# ui_password TITLE TEXT: prints the answer (never echoed to the screen).
ui_password() {
  local a
  case $(ui_mode) in
    dialog) a=$(_dlg --title "$1" --insecure --passwordbox "$2" 0 0) || return 1 ;;
    plain) printf '\n%s\n%s: ' "$1" "$2" >"$REZ_TTY"; IFS= read -rs a <"$REZ_TTY" || a=''; printf '\n' >"$REZ_TTY" ;;
    none) die "$1: a password is needed; provide it with --config" ;;
  esac
  printf '%s' "$a"
}

# ui_menu TITLE TEXT DEFAULT TAG ITEM [TAG ITEM...]: prints the chosen tag.
ui_menu() {
  local title=$1 text=$2 def=$3; shift 3
  local -a tags=() items=()
  while (($#)); do tags+=("$1"); items+=("$2"); shift 2; done
  case $(ui_mode) in
    dialog)
      local -a args=()
      local i
      for i in "${!tags[@]}"; do args+=("${tags[$i]}" "${items[$i]}"); done
      _dlg --title "$title" --default-item "$def" --menu "$text" 0 0 0 "${args[@]}"
      ;;
    plain)
      local i a
      printf '\n== %s ==\n%s\n' "$title" "$text" >"$REZ_TTY"
      for i in "${!tags[@]}"; do
        printf '  %d) %-10s %s%s\n' $((i + 1)) "${tags[$i]}" "${items[$i]}" \
          "$([[ ${tags[$i]} == "$def" ]] && echo '  (default)')" >"$REZ_TTY"
      done
      while :; do
        printf 'Choose 1-%d [default %s]: ' "${#tags[@]}" "$def" >"$REZ_TTY"
        a=$(_tty_read)
        [[ -z "$a" ]] && { printf '%s' "$def"; return 0; }
        if [[ "$a" =~ ^[0-9]+$ ]] && ((a >= 1 && a <= ${#tags[@]})); then
          printf '%s' "${tags[$((a - 1))]}"; return 0
        fi
      done
      ;;
    none) printf '%s' "$def" ;;
  esac
}

# ui_checklist TITLE TEXT TAG ITEM on|off|locked [...]: prints chosen tags,
# comma-separated. "locked" items are shown but cannot be selected.
ui_checklist() {
  local title=$1 text=$2; shift 2
  local -a tags=() items=() states=()
  while (($#)); do tags+=("$1"); items+=("$2"); states+=("$3"); shift 3; done
  local i out=''
  case $(ui_mode) in
    dialog)
      local -a args=()
      for i in "${!tags[@]}"; do
        [[ "${states[$i]}" == locked ]] && continue
        args+=("${tags[$i]}" "${items[$i]}" "${states[$i]}")
      done
      out=$(_dlg --title "$title" --separate-output --checklist "$text" 0 0 0 "${args[@]}") || return 1
      out=$(tr '\n' ',' <<<"$out"); out=${out%,}
      ;;
    plain)
      local a n
      while :; do
        printf '\n== %s ==\n%s\n' "$title" "$text" >"$REZ_TTY"
        for i in "${!tags[@]}"; do
          case "${states[$i]}" in
            on) printf '  %2d) [x] %-12s %s\n' $((i + 1)) "${tags[$i]}" "${items[$i]}" ;;
            off) printf '  %2d) [ ] %-12s %s\n' $((i + 1)) "${tags[$i]}" "${items[$i]}" ;;
            locked) printf '      [-] %-12s %s\n' "${tags[$i]}" "${items[$i]}" ;;
          esac >"$REZ_TTY"
        done
        printf 'Numbers to toggle (e.g. "3 5"), Enter when done: ' >"$REZ_TTY"
        a=$(_tty_read)
        [[ -z "$a" ]] && break
        for n in ${a//,/ }; do
          [[ "$n" =~ ^[0-9]+$ ]] || continue
          ((n >= 1 && n <= ${#tags[@]})) || continue
          i=$((n - 1))
          case "${states[$i]}" in on) states[i]=off ;; off) states[i]=on ;; esac
        done
      done
      for i in "${!tags[@]}"; do [[ "${states[$i]}" == on ]] && out+="${out:+,}${tags[$i]}"; done
      ;;
    none)
      for i in "${!tags[@]}"; do [[ "${states[$i]}" == on ]] && out+="${out:+,}${tags[$i]}"; done
      ;;
  esac
  printf '%s' "$out"
}
