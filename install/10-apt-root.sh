#!/bin/bash
# PPAs and apt packages (runtime + build). Root.
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "Hyprland PPA (cppiber/hyprland: Hyprland >= 0.55 with Lua config, uwsm, hyprsunset, wayland-protocols >= 1.41)"
ppa_source cppiber/hyprland

# The two vendor sources are deb822 files: a release upgrade turns those off
# (Enabled: no) and the check below turns them on again, where the one-line
# .list the port wrote before could not be migrated and left .list.migrate and
# .list.disabled copies behind. lists_superseded <name>: the old .list and those
# copies go, once its .sources is in place.
lists_superseded() {
  rm -f "/etc/apt/sources.list.d/$1.list" "/etc/apt/sources.list.d/$1.list.migrate" "/etc/apt/sources.list.d/$1.list.disabled"
}

# Omarchy's base ships the 1Password app and CLI; on Ubuntu they come from 1Password's
# own repository. The 1password package writes the same .sources and keeps it
# current once installed (and comments out a .list it finds).
log "1Password repository (app and CLI, as Omarchy's base)"
if ! apt_source_active https://downloads.1password.com/linux/debian/amd64 stable; then
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --yes -o /usr/share/keyrings/1password-archive-keyring.gpg
  install_file 644 /etc/apt/sources.list.d/1password.sources <<'EOF'
Types: deb
URIs: https://downloads.1password.com/linux/debian/amd64
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/1password-archive-keyring.gpg
EOF
fi
[[ ! -f /etc/apt/sources.list.d/1password.sources ]] || lists_superseded 1password

# Omarchy's bar has a Tailscale widget and dots setup joins the tailnet: the package
# comes from Tailscale's repository, which has one suite per Ubuntu release
log "Tailscale repository"
if ! apt_source_active https://pkgs.tailscale.com/stable/ubuntu "$UBUNTU_CODENAME" ||
  grep -qs 'pkgs\.tailscale\.com' /etc/apt/sources.list.d/tailscale.list; then
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$UBUNTU_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  install_file 644 /etc/apt/sources.list.d/tailscale.sources <<EOF
Types: deb
URIs: https://pkgs.tailscale.com/stable/ubuntu
Suites: $UBUNTU_CODENAME
Components: main
Signed-By: /usr/share/keyrings/tailscale-archive-keyring.gpg
EOF
  lists_superseded tailscale
fi

apt_retry update -qq

# Omarchy's editor config is LazyVim's, which wants neovim 0.11.2; noble's
# archive has 0.9, 26.04's a current one.
nvim=$(apt_candidate neovim)
if [[ -z $nvim ]] || dpkg --compare-versions "$nvim" lt 0.11.2; then
  log "Neovim PPA (neovim-ppa/stable): the archive's neovim is ${nvim:-none}"
  ppa_source neovim-ppa/stable
  apt_retry update -qq
else
  ppa_leftovers neovim-ppa/stable
fi

# --release (the updater, after a release upgrade): Ubuntu's upgrade kept what
# came from the sources it turned off at the old release's builds, and held
# back what those link (Qt, for cppiber's portal). cppiber's noble builds sort
# above its builds for a later release (0.5.1-1ppa3 > 0.5.1-1ppa3~1resolute1),
# so apt would keep them: for this one full upgrade a pin above 1000 takes the
# PPA's builds for this release, downgrades included, and the rest moves
# along with them, as the release upgrade would have moved it with the PPA on.
if [[ ${1:-} == --release ]]; then
  log "packages from the sources back on, to the new release's builds"
  realign=/etc/apt/preferences.d/omarchy-release-realign
  trap 'rm -f "$realign"' EXIT
  printf 'Package: *\nPin: release o=LP-PPA-cppiber-hyprland\nPin-Priority: 1001\n' >"$realign"
  apt_retry -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade -y --allow-downgrades
  rm -f "$realign"
  trap - EXIT
fi

read_list() { grep -vE '^\s*(#|$)' "$1"; }
mapfile -t runtime < <(read_list "$REPO_DIR/packages/apt-runtime.txt")
mapfile -t build < <(read_list "$REPO_DIR/packages/apt-build.txt")

packaged=()
while read -r p; do
  [[ -z $(apt_candidate "$p") ]] || packaged+=("$p")
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
