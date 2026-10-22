#!/bin/bash
# PPAs and apt packages (runtime + build). Root.
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "Hyprland PPA (cppiber/hyprland: Hyprland >= 0.55 with Lua config, uwsm, hyprsunset, wayland-protocols >= 1.41)"
ppa_source cppiber/hyprland

# Omarchy's base ships the 1Password app and CLI; on Ubuntu they come from 1Password's
# own repository (its packages keep the source file current once installed)
log "1Password repository (app and CLI, as Omarchy's base)"
if ! apt_source_active https://downloads.1password.com/linux/debian/amd64 stable; then
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --yes -o /usr/share/keyrings/1password-archive-keyring.gpg
  echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' >/etc/apt/sources.list.d/1password.list
fi

# Omarchy's bar has a Tailscale widget and dots setup joins the tailnet: the package
# comes from Tailscale's repository, which has one suite per Ubuntu release
log "Tailscale repository"
if ! apt_source_active https://pkgs.tailscale.com/stable/ubuntu "$UBUNTU_CODENAME"; then
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$UBUNTU_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$UBUNTU_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
fi

apt_retry update -qq

# Omarchy's editor config is LazyVim's, which wants neovim 0.11.2; noble's
# archive has 0.9, 26.04's a current one.
nvim=$(apt-cache policy neovim | awk '/^  Candidate:/ { print $2 }')
if [[ -z $nvim || $nvim == "(none)" ]] || dpkg --compare-versions "$nvim" lt 0.11.2; then
  log "Neovim PPA (neovim-ppa/stable): the archive's neovim is ${nvim:-none}"
  ppa_source neovim-ppa/stable
  apt_retry update -qq
fi

read_list() { grep -vE '^\s*(#|$)' "$1"; }
mapfile -t runtime < <(read_list "$REPO_DIR/packages/apt-runtime.txt")
mapfile -t build < <(read_list "$REPO_DIR/packages/apt-build.txt")

packaged=()
while read -r p; do
  candidate=$(apt-cache policy "$p" | awk '/^  Candidate:/ { print $2 }')
  [[ -z $candidate || $candidate == "(none)" ]] || packaged+=("$p")
done < <(read_list "$REPO_DIR/packages/apt-if-packaged.txt")

log "apt packages"
apt_retry install -y --no-install-recommends "${runtime[@]}" "${build[@]}" "${packaged[@]}"

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

# ImageMagick 6 (noble) has no `magick` entry point; Omarchy scripts call
# `magick`. ImageMagick 7 (26.04) links it as an alternative, which the shim,
# still in place after an upgrade from noble, would keep from being linked.
if update-alternatives --query magick >/dev/null 2>&1; then
  if grep -qs 'Ubuntu 24.04 ships ImageMagick 6' /usr/bin/magick; then
    rm -f /usr/bin/magick
    update-alternatives --auto magick
    note "removed the /usr/bin/magick shim: ImageMagick 7's own magick takes its place"
  fi
elif [[ ! -x /usr/bin/magick ]]; then
  install -Dm755 /dev/stdin /usr/bin/magick <<'EOF'
#!/bin/sh
# Ubuntu 24.04 ships ImageMagick 6: `magick` is `convert` there.
exec convert "$@"
EOF
  note "installed /usr/bin/magick shim (omarchy-plymouth-set runs with PATH=/usr/bin:/bin)"
fi

# libvips 8.15 (noble) spells vipsthumbnail's output option -o; upstream's
# scripts pass --path (8.16+, 26.04 has 8.18). A wrapper ahead of /usr/bin
# keeps the scripts untouched where the archive's lacks it.
vips_wrapper=/usr/local/bin/vipsthumbnail
if /usr/bin/vipsthumbnail --help 2>&1 | grep -- '--path=' >/dev/null; then
  if grep -qs 'whose vipsthumbnail takes -o' "$vips_wrapper"; then
    rm -f "$vips_wrapper"
    note "removed $vips_wrapper: the archive's vipsthumbnail takes --path"
  fi
else
  install -Dm755 /dev/stdin "$vips_wrapper" <<'EOF'
#!/bin/sh
# Ubuntu 24.04 ships libvips 8.15, whose vipsthumbnail takes -o where 8.16+ takes --path.
set -- "$@" --
while [ "$1" != -- ]; do
  case $1 in
    --path) set -- "$@" -o ;;
    --path=*) set -- "$@" -o "${1#--path=}" ;;
    *) set -- "$@" "$1" ;;
  esac
  shift
done
shift
exec /usr/bin/vipsthumbnail "$@"
EOF
  note "installed $vips_wrapper wrapper (--path -> -o)"
fi
