#!/bin/bash
# PPAs and apt packages (runtime + build). Root.
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "Hyprland PPA (cppiber/hyprland: Hyprland >= 0.55 with Lua config, uwsm, hyprsunset, wayland-protocols >= 1.41)"
if ! ls /etc/apt/sources.list.d/ | grep -q cppiber; then
  add-apt-repository -y ppa:cppiber/hyprland
fi

apt-get update -qq

read_list() { grep -vE '^\s*(#|$)' "$1"; }
mapfile -t runtime < <(read_list "$REPO_DIR/packages/apt-runtime.txt")
mapfile -t build < <(read_list "$REPO_DIR/packages/apt-build.txt")

log "apt packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${runtime[@]}" "${build[@]}"

# ImageMagick 6 has no `magick` entry point; Omarchy scripts call `magick`.
if ! have magick; then
  install -Dm755 /dev/stdin /usr/local/bin/magick <<'EOF'
#!/bin/sh
# Ubuntu 24.04 ships ImageMagick 6: `magick` is `convert` there.
exec convert "$@"
EOF
  note "installed /usr/local/bin/magick shim"
fi
