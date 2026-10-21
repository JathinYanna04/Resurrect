# shellcheck shell=bash
# `rez setup`: detect -> recommend -> choose -> configure -> review -> install.
# Same pipeline with and without prompts; flags and --config answer the
# questions in non-interactive mode.

[[ -n "${_REZ_SETUP_LOADED:-}" ]] && return 0
_REZ_SETUP_LOADED=1

setup_usage() {
  cat <<'EOF'
Usage: rez setup [options]
  --profile lite|standard|full   start from a profile (default: recommended for this device)
  --modules a,b,c                install exactly these modules (dependencies are added)
  --config FILE                  answers in key=value form (see config/resurrect.conf.example)
  --root ask|yes|no              check for root (ask = Magisk shows a prompt); default: ask
                                 when interactive, no otherwise
  -y, --yes                      non-interactive, accept the plan
  --dry-run                      show the plan and every command, change nothing
EOF
}

setup_main() {
  local profile='' modules='' root_mode='' conf=''
  while (($#)); do
    case "$1" in
      --profile) profile=${2:?--profile needs a value}; shift ;;
      --profile=*) profile=${1#*=} ;;
      --modules) modules=${2:?--modules needs a value}; shift ;;
      --modules=*) modules=${1#*=} ;;
      --config) conf=${2:?--config needs a file}; shift ;;
      --config=*) conf=${1#*=} ;;
      --root) root_mode=${2:?--root needs ask, yes or no}; shift ;;
      --root=*) root_mode=${1#*=} ;;
      -h | --help) setup_usage; return 0 ;;
      *) die "unknown setup option: $1 (see rez setup --help)" ;;
    esac
    shift
  done

  is_termux || [[ "${REZ_ALLOW_NON_TERMUX:-0}" == 1 ]] \
    || die "rez setup must run inside Termux on Android (set REZ_ALLOW_NON_TERMUX=1 for testing)"
  rez_init_dirs
  [[ -n "$conf" ]] && cfg_import "$conf"
  [[ -n "$profile" ]] || profile=$(cfg_get profile "")
  [[ -n "$modules" ]] || modules=$(cfg_get setup.modules "")
  [[ -n "$root_mode" ]] || root_mode=$(cfg_get setup.root "")
  if [[ -z "$root_mode" ]]; then
    [[ $(ui_mode) == none ]] && root_mode=no || root_mode=ask
  fi

  # 1. Detect
  info "detecting device"
  detect_all
  case "$root_mode" in
    yes) detect_root ask; [[ "$REZ_HAS_ROOT" == yes ]] || die "--root yes, but root was not granted" ;;
    ask)
      if [[ "$DEV_ROOT" == available ]] && ui_yesno "Root" \
        "This device has su${DEV_ROOT_KIND:+ ($DEV_ROOT_KIND)}. Check root now? Your root manager will ask for permission.

Root is optional. It only unlocks AdGuard Home on port 53 and the ACC charge limit." yes; then
        detect_root ask
      fi
      ;;
    no) REZ_HAS_ROOT=no ;;
    *) die "--root must be ask, yes or no" ;;
  esac
  [[ "$REZ_HAS_ROOT" == yes ]] || REZ_HAS_ROOT=no
  export REZ_HAS_ROOT
  cfg_set device.root "$REZ_HAS_ROOT"

  # 2. Summary and warnings
  ui_msg "Your device" "$(detect_report)"
  local warnings
  warnings=$(setup_warnings)
  [[ -n "$warnings" ]] && ui_msg "Before you continue" "$warnings"

  # 3. Profile
  local rec
  rec=$(recommend_profile)
  if [[ -z "$profile" ]]; then
    profile=$(ui_menu "Profile" "Recommended for ${DEV_MEM_TOTAL_MB} MB RAM: $rec. You can add or remove modules next." "$rec" \
      lite "Lite: passwords, alerts, remote access, backups (<3 GB RAM)" \
      standard "Standard: + ad blocking, file sharing, sync, smart alerts (3-5 GB)" \
      full "Full: + Jellyfin media server (6 GB+, SD card)") || die "cancelled"
  fi
  [[ "$profile" =~ ^(lite|standard|full)$ ]] || die "unknown profile: $profile"
  cfg_set profile "$profile"

  # 4. Modules
  local chosen
  if [[ -n "$modules" ]]; then
    chosen=$modules
  else
    chosen=$(setup_checklist "$(profile_modules "$profile")") || die "cancelled"
  fi
  local list=() m why
  for m in $(modules_sorted "$chosen"); do
    if why=$(module_ineligible "$m"); then
      warn "skipping $m: $why"
      continue
    fi
    list+=("$m")
  done
  ((${#list[@]})) || die "nothing to install"
  csv_has "$(IFS=,; echo "${list[*]}")" base || die "the base module is required"

  # 5. Per-module questions (answers are stored in the config file).
  # Modules can see what else is being installed through REZ_SETUP_MODULES.
  REZ_SETUP_MODULES=$(IFS=,; echo "${list[*]}")
  export REZ_SETUP_MODULES
  for m in "${list[@]}"; do
    module_call "$m" configure || die "$m: configuration failed"
  done

  # 6. Review
  local plan
  plan=$(setup_plan "${list[@]}")
  if [[ "$REZ_DRY_RUN" == 1 ]]; then
    printf '%s\n' "$plan"
  fi
  ui_yesno "Review" "$plan

Install now?" yes || { info "nothing installed. Your answers are saved; run rez setup again any time."; return 0; }

  # 7. Install
  for m in "${list[@]}"; do
    setup_install_one "$m"
  done
  base_sync_boot_and_cron

  # 8. Finish
  info "running checks"
  doctor_main --quiet || true
  setup_finish "${list[@]}"
}

setup_warnings() {
  local w=''
  [[ "$DEV_TERMUX_SOURCE" == GOOGLE_PLAY_STORE ]] && w+="* Termux from Google Play is outdated and breaks package installs. Install Termux from F-Droid or GitHub instead.
"
  [[ "$DEV_PHANTOM" == active || "$DEV_PHANTOM" == unknown ]] && w+="* Android $DEV_ANDROID can kill background processes (\"phantom process killer\"). Servers will die at random until you turn it off: see rez doctor or docs/troubleshooting.
"
  [[ "$DEV_TERMUX_BOOT" == no ]] && w+="* Termux:Boot is not installed. Without it nothing starts after a reboot. Install it from the same place you got Termux, then open it once.
"
  [[ -n "$DEV_BOOT_EXTRA" ]] && w+="* ~/.termux/boot/ already contains: $DEV_BOOT_EXTRA. Termux:Boot runs EVERY file there. Setup will offer to move them to ~/.termux/boot-disabled/.
"
  [[ "$DEV_ARCH" == armv7 || "$DEV_ARCH" == 386 ]] && w+="* 32-bit device: some modules are not available.
"
  ((DEV_FREE_HOME_MB < 2048)) && w+="* Only ${DEV_FREE_HOME_MB} MB free. 2 GB or more is recommended.
"
  w+="* Exclude Termux from battery optimization: Android Settings > Apps > Termux > Battery > Unrestricted."
  printf '%s' "$w"
}

# setup_checklist PROFILE_MODULES: interactive module picker.
setup_checklist() {
  local pre=$1 m why state desc args=()
  for m in "${REZ_MODULE_ORDER[@]}"; do
    desc=$(module_meta "$m" DESC)
    [[ "$(module_meta "$m" ROOT)" == required ]] && desc="(root) $desc"
    if why=$(module_ineligible "$m"); then
      state=locked desc="$desc  [$why]"
    elif csv_has "$pre" "$m" || [[ "$m" == base ]]; then
      state=on
    elif [[ "$m" == acc && "$REZ_HAS_ROOT" == yes ]]; then
      state=on
    else
      state=off
    fi
    args+=("$m" "$desc" "$state")
  done
  ui_checklist "Modules" "Pick what to run. Space toggles, Enter confirms. Dependencies are added automatically." "${args[@]}"
}

setup_plan() {
  local m ram=0 disk=0 ports='' r d p
  printf 'Modules: %s\n' "$*"
  for m in "$@"; do
    r=$(module_meta "$m" RAM_EST_MB); d=$(module_meta "$m" DISK_EST_MB); p=$(module_meta "$m" PORTS)
    ram=$((ram + r)); disk=$((disk + d))
    [[ -n "$p" ]] && ports+="$m:$p "
  done
  printf 'Estimated RAM in use: ~%s MB (MemAvailable now: %s MB)\n' "$ram" "$DEV_MEM_AVAIL_MB"
  printf 'Estimated download/disk: ~%s MB (free: %s MB)\n' "$disk" "$DEV_FREE_HOME_MB"
  printf 'Ports: %s\n' "${ports:-none}"
  printf 'Startup: one script, ~/.termux/boot/resurrect\n'
  printf 'Root: %s\n' "$REZ_HAS_ROOT"
  if ((ram > DEV_MEM_AVAIL_MB * 8 / 10)); then
    printf '\nWARNING: this is close to or above the free memory. Consider fewer modules.\n'
  fi
}

# setup_install_one MODULE: install (idempotent), record, start.
setup_install_one() {
  local m=$1 why
  if why=$(module_ineligible "$m"); then
    die "$m cannot be installed here: $why"
  fi
  info "installing $m"
  if ! module_call "$m" install; then
    die "$m failed to install. Fix the problem above and run the same command again; finished steps are skipped."
  fi
  cfg_list_add modules "$m"
  if [[ "$(cfg_get "$m.autostart" yes)" != no ]]; then
    module_call "$m" start || warn "$m installed but did not start; see rez logs $m"
  fi
}

setup_finish() {
  local m info_text=''
  for m in "$@"; do
    info_text+=$(module_call "$m" info 2>/dev/null || true)
    info_text+=$'\n'
  done
  ui_msg "Done" "resurrect is running.

$info_text
Next steps:
* Open Termux:Boot once so Android lets it start at boot.
* Reboot when convenient and run 'rez status' to check everything came back.
* Read docs/security.md.

Commands: rez status | rez doctor | rez help"
}

# base_sync_boot_and_cron: (re)write the boot entry and the cron block from
# the installed modules. Safe to run any time.
base_sync_boot_and_cron() {
  if csv_has "$(cfg_get modules "")" base; then
    boot_install_script
  fi
  local m lines=''
  for m in $(modules_enabled); do
    lines+=$(module_call "$m" cron 2>/dev/null || true)
    [[ -n "$lines" && "${lines: -1}" != $'\n' ]] && lines+=$'\n'
  done
  if have crontab; then
    printf '%s' "$lines" | cron_install_block
  else
    [[ -z "$lines" ]] || warn "crontab not available; scheduled jobs not installed"
  fi
}

boot_install_script() {
  local f="$REZ_BOOT_DIR/resurrect" tmp
  ensure_dir 700 "$REZ_BOOT_DIR"
  tmp=$(sed -e "s|/data/data/com.termux/files/usr|$PREFIX|g" -e "s|@REZ_ROOT@|$REZ_ROOT|g" "$REZ_ROOT/boot/resurrect-boot.sh")
  if [[ -f "$f" ]] && [[ "$(cat "$f")" == "$tmp" ]]; then
    debug "boot script up to date"
  else
    printf '%s\n' "$tmp" | atomic_write "$f" 700
    ok "boot script written: $f"
  fi
  boot_check_extra
}

# Termux:Boot runs every file in ~/.termux/boot. Anything besides ours is
# a second startup path: offer to move it aside (never delete).
boot_check_extra() {
  local f extra=()
  for f in "$REZ_BOOT_DIR"/* "$REZ_BOOT_DIR"/.[!.]*; do
    [[ -e "$f" && "${f##*/}" != resurrect ]] && extra+=("$f")
  done
  ((${#extra[@]})) || return 0
  local names
  names=$(printf '  %s\n' "${extra[@]##*/}")
  if [[ "$(cfg_get base.move_boot_files "")" == yes ]] || { [[ $(ui_mode) != none ]] && ui_yesno "Other boot scripts" \
    "Termux:Boot runs EVERY file in ~/.termux/boot/, so these also run at every boot:
$names
Running two startup scripts is how services end up started twice.
Move them to ~/.termux/boot-disabled/ (nothing is deleted)?" yes; }; then
    ensure_dir 700 "$HOME/.termux/boot-disabled"
    for f in "${extra[@]}"; do
      run mv -n "$f" "$HOME/.termux/boot-disabled/"
    done
    ok "moved ${#extra[@]} file(s) to ~/.termux/boot-disabled/"
  else
    warn "other files in ~/.termux/boot/ will also run at boot:
$names"
  fi
}
