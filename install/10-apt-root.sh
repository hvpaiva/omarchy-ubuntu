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

mapfile -t replaced < <(read_list "$REPO_DIR/packages/apt-replaced.txt")
present=()
for p in "${replaced[@]}"; do
  apt_installed "$p" && present+=("$p")
done
if ((${#present[@]})); then
  log "packages the shell replaces: ${present[*]}"
  extra=$(LC_ALL=C apt-get -s purge "${present[@]}" | awk '$1 == "Purg" || $1 == "Remv" {print $2}' | grep -vxF -f <(printf '%s\n' "${present[@]}") || true)
  if [[ -n $extra ]]; then
    warn "purging them would also remove $(tr '\n' ' ' <<<"$extra"); left installed, 65-session.sh masks their units"
  else
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "${present[@]}"
  fi
fi

# ImageMagick 6 has no `magick` entry point; Omarchy scripts call `magick`.
if [[ ! -x /usr/bin/magick ]]; then
  install -Dm755 /dev/stdin /usr/bin/magick <<'EOF'
#!/bin/sh
# Ubuntu 24.04 ships ImageMagick 6: `magick` is `convert` there.
exec convert "$@"
EOF
  note "installed /usr/bin/magick shim (omarchy-plymouth-set runs with PATH=/usr/bin:/bin)"
fi
