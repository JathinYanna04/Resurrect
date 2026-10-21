# shellcheck shell=bash
# Pinned upstream versions and checksums. Every download is verified against
# these values; a mismatch aborts the install. Bump a version only together
# with its checksums (scripts/update-pins.sh prints fresh ones).
#
# Keys: <tool>_<goarch>, goarch = arm64 | armv7 | amd64 | 386.
# shellcheck disable=SC2034  # read indirectly through pin_sha256

PIN_TAILSCALE_VERSION="1.102.4"
PIN_TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_\${version}_\${arch}.tgz"
# Tailscale names armv7 "arm".
declare -gA PIN_TAILSCALE_SHA256=(
  [arm64]=9dd1e6a592a014bbaea0103167ffe299adeda4ba14e078ce9c2895364f6c4c3f
  [armv7]=b981a59cb85fb923ee6e1860ee6934772c83a840a6627f0dbfd7711ed690b869
  [amd64]=50748df1045e60b5b695f19f4c56b0da36c019948b440fb456b6584a50f0d8b9
  [386]=44730cacea956ffdbe145e7c1dae05668ca61febdde3ef764bba75d20c8d0b8e
)

PIN_NTFY_VERSION="2.32.0"
PIN_NTFY_URL="https://github.com/binwiederhier/ntfy/releases/download/v\${version}/ntfy_\${version}_linux_\${arch}.tar.gz"
declare -gA PIN_NTFY_SHA256=(
  [arm64]=408c34d833f5fa7cc1a05b8fa43ea6f2b78a42bd8ea2f9248bc728e78b90a891
  [armv7]=feda554c21ef68176b0defa704815eec64d5751557fa16eb041de778d9c2b476
  [amd64]=681819773a69079c0efdd64c096cc2149d9290243feb3e31dd3ef04a2c85f1ed
)

PIN_FILEBROWSER_VERSION="2.63.23"
PIN_FILEBROWSER_URL="https://github.com/filebrowser/filebrowser/releases/download/v\${version}/linux-\${arch}-filebrowser.tar.gz"
declare -gA PIN_FILEBROWSER_SHA256=(
  [arm64]=c55b3450b6ac07ef73b5b49f0b2955a8e755100b71af1df73f9e5d25b12fd27a
  [armv7]=dee508c90f30434cb7cce0cac5359dece2e938792bbcaff03cbccb7f8e37bd8c
  [amd64]=b14db2bb8033caa3f80205eb6578b2ed0744ebd9e716b790bc4a9703ce909e88
  [386]=3c9202ef93e7176f82e67aff4859a82344f44527b95079b8c4df931e95306340
)

PIN_ADGUARD_VERSION="0.107.79"
PIN_ADGUARD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/v\${version}/AdGuardHome_linux_\${arch}.tar.gz"
declare -gA PIN_ADGUARD_SHA256=(
  [arm64]=3f7893c18e8aaadc456d0452839190561c306ca95175a2254958be80a769c1ae
  [armv7]=7f8a4135ed427c5faafbc52d29845ea42acb38818bd7648626ddc07ee61a999e
  [amd64]=c48f4a43000665484c5ec28177de11a004759b620dae8f77b2aabefc9ef3687f
  [386]=e9a90f94f34d78e6d165f57b968a71aae0ba0233868246fff98cbef5f43fad30
)

# Vaultwarden has no standalone Linux binaries; the official Alpine image
# ships a static musl build. We pull the per-arch image manifest by digest
# (content-addressed, so the digest is the checksum) and extract the binary.
PIN_VAULTWARDEN_VERSION="1.37.4"
PIN_VAULTWARDEN_IMAGE="vaultwarden/server"
declare -gA PIN_VAULTWARDEN_SHA256=(
  [arm64]=c82bc74bb0a88821fd3fbce48e7867e8aca4e492e512970a309d02a629ab91d4
  [armv7]=075794f469a467dbc9b77bdbae8dc1e6dd327af4ef18ac18ebcfa2ac8530b9c8
  [amd64]=7d90670a4e2531e752f014e58f7283b9d197847b6f073bf84e99598f49d80ffd
)

# copyparty is a pure-Python wheel with no dependencies; pip installs it with
# --require-hashes so the wheel is verified like everything else.
PIN_COPYPARTY_VERSION="1.20.26"
PIN_COPYPARTY_WHEEL_SHA256="7e51a2576699c089fe6ad74dfd59db02575eb4211af8870372b10a63caf611cb"

PIN_ACC_VERSION="v2023.10.16"
PIN_ACC_URL="https://github.com/VR-25/acc/releases/download/v2023.10.16/acc_v2023.10.16_202310160.zip"
PIN_ACC_SHA256="fe071f77a6300f1c14aee1ffc8e22452e448635a7a40e6d97480f3b44fb8c795"
