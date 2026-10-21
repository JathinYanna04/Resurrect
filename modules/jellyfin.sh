# shellcheck shell=bash
# jellyfin: media server. Only offered with enough RAM and an SD card or
# other external storage for the media.
#
# Phone-friendly defaults: runs in Debian (proot), .NET heap capped, all
# transcoding off (phone SoCs have no usable transcoding from Linux, so
# clients must direct-play), not started at boot unless you ask for it.

MOD_NAME=jellyfin
MOD_DESC="Jellyfin media server (direct play only; needs RAM + SD/external)"
MOD_DEPENDS="base"
MOD_MIN_RAM_MB=3500
MOD_NEEDS_EXTERNAL=1
MOD_ARCHES="arm64 amd64"
MOD_PORTS="8096"
MOD_RAM_EST_MB=350
MOD_DISK_EST_MB=900
MOD_TESTED="no (largest module; logic reviewed only)"

_media() { cfg_get media.path "${DEV_SD_PATH:-}"; }

mod_configure() {
  cfg_set media.path "$(cfg_get media.path "$(ui_input "Jellyfin" "Media folder (read-only inside Jellyfin). Run termux-setup-storage first so Termux can read the SD card." "${DEV_SD_PATH:-}" required)")"
  cfg_set jellyfin.heap_mb "$(cfg_get jellyfin.heap_mb 300)"
  [[ -n "$(cfg_get jellyfin.autostart "")" ]] || {
    local a=no
    ui_yesno "Jellyfin" "Start Jellyfin at every boot? (It uses ~300 MB of RAM; you can start it on demand with: rez start jellyfin)" no && a=yes
    cfg_set jellyfin.autostart "$a"
  }
}

mod_install() {
  proot_install
  local codename='<debian-codename>'
  # shellcheck disable=SC2016  # expanded inside Debian, not here
  [[ "$REZ_DRY_RUN" == 1 ]] || codename=$(proot_exec sh -c '. /etc/os-release && echo "$VERSION_CODENAME"')
  run_cmd proot_exec sh -c "set -e
    apt-get install -y --no-install-recommends gnupg
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/jellyfin.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/debian $codename main' > /etc/apt/sources.list.d/jellyfin.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jellyfin-server jellyfin-web jellyfin-ffmpeg7"
  ok "Jellyfin installed in Debian. In its dashboard: Playback > Transcoding > hardware acceleration None, and disable transcoding for each user."
}

mod_start() {
  local heap media
  heap=$(cfg_get jellyfin.heap_mb 300)
  media=$(_media)
  [[ -d "$media" ]] || die "media folder not readable: $media (run termux-setup-storage?)"
  # Media appears at /media inside Debian (add it as a library there).
  # Jellyfin listens on every interface; restrict it under Dashboard > Networking.
  svc_start jellyfin jellyfin "" -- proot-distro login "$REZ_PROOT_DISTRO" --bind "$media:/media" -- \
    env DOTNET_GCHeapHardLimit="$(printf '0x%x' $((heap * 1024 * 1024)))" \
    /usr/bin/jellyfin --datadir /var/lib/jellyfin --cachedir /var/cache/jellyfin \
    --webdir /usr/share/jellyfin/web --ffmpeg /usr/lib/jellyfin-ffmpeg/ffmpeg
}

mod_stop() { svc_stop jellyfin jellyfin; }
mod_status() { svc_status_line jellyfin jellyfin "" "port 8096, media $(_media), autostart $(cfg_get jellyfin.autostart no)"; }
mod_health() { svc_running jellyfin jellyfin && port_open 127.0.0.1 8096; }

mod_backup() {
  local root
  root=$(proot_rootfs) || return 0
  mkdir -p "$1"
  # Library database and settings; metadata/images are re-creatable.
  tar -C "$root/var/lib/jellyfin" -cf "$1/jellyfin.tar" --exclude=metadata --exclude=cache . 2>/dev/null || true
}

mod_uninstall() {
  run_cmd proot_exec apt-get remove -y jellyfin-server jellyfin-web jellyfin-ffmpeg7
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd proot_exec rm -rf /var/lib/jellyfin /var/cache/jellyfin
  return 0
}

mod_info() { printf 'Jellyfin:   http://%s:8096 (start on demand: rez start jellyfin)\n' "$(device_host)"; }
