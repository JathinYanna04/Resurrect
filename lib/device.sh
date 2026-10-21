# shellcheck shell=bash
# `rez device`: what this phone is and what its owner could do with it.
# Strictly read-only. resurrect never unlocks bootloaders, never flashes,
# never reboots into a recovery or fastboot mode. It explains and links.

[[ -n "${_REZ_DEVICE_LOADED:-}" ]] && return 0
_REZ_DEVICE_LOADED=1

# bootloader_state: locked | unlocked | unknown (from read-only properties).
bootloader_state() {
  local v
  v=$(prop ro.boot.flash.locked)
  case "$v" in
    1) echo locked; return ;;
    0) echo unlocked; return ;;
  esac
  v=$(prop ro.boot.verifiedbootstate)
  case "$v" in
    green) echo locked ;;
    orange) echo unlocked ;;
    *) echo unknown ;;
  esac
}

device_guide() {
  local bl codename_lc
  bl=$(bootloader_state)
  codename_lc=${DEV_CODENAME,,}
  detect_report
  cat <<EOF
Bootloader:  $bl (read from system properties; may be wrong on some vendors)

resurrect works on the ROM you have now. Nothing below is required.

Custom ROM options for "$DEV_CODENAME"
  A newer, maintained ROM brings security updates and often frees RAM.
  Check whether your device has official support (look it up by codename,
  then by model name, since names differ between projects):
    LineageOS:    https://wiki.lineageos.org/devices/$codename_lc/
                  (all devices: https://wiki.lineageos.org/devices/)
    postmarketOS: https://wiki.postmarketos.org/wiki/Devices
    Others:       search your model on XDA forums (xdaforums.com)
  Follow ONLY the official install guide for your exact model and variant.

  Before you do anything:
    * Unlocking the bootloader ERASES ALL DATA on the phone.
    * It can void the warranty, and some vendors refuse unlocking entirely
      or require an online request and waiting period.
    * Flashing the wrong file or interrupting a flash can BRICK the device.
    * Banking, payment and some streaming apps may stop working.
    * resurrect will never do any of this for you. See docs/custom-rom.md.

Root (optional)
  Root only adds: AdGuard Home on port 53, the ACC charge limit.
  Status: $DEV_ROOT${DEV_ROOT_KIND:+ ($DEV_ROOT_KIND)}
  Guide: docs/rooting.md (manual, step by step, with the same warnings).

To share these details in a GitHub issue: rez device --report
EOF
}
