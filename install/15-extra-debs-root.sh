#!/bin/bash
# Tools that Ubuntu does not package: official .deb releases. Root (dpkg).
source "${REPO_DIR:?}/lib/common.sh"
need_root

install_deb() { # install_deb <name> <github repo> <tag> <asset>
  local name=$1 repo=$2 tag=$3 asset=$4
  if apt_installed "$name"; then
    note "unchanged $name"
    return
  fi
  log "$name from $repo $tag"
  su -s /bin/bash "$OMARCHY_USER" -c "REPO_DIR='$REPO_DIR'; source '$REPO_DIR/lib/common.sh'; github_release_download '$repo' '$tag' '$asset'"
  apt-get install -y "$DOWNLOADS/$asset"
}

# gum: the TUI toolkit every omarchy-* prompt uses.
install_deb gum charmbracelet/gum "v$GUM_VERSION" "gum_${GUM_VERSION}_amd64.deb"

# LocalSend: Super+Ctrl+S share menu (`localsend --headless send`).
install_deb localsend localsend/localsend "v$LOCALSEND_VERSION" "LocalSend-${LOCALSEND_VERSION}-linux-x86-64.deb"

# Voxtype: dictation (Super+Ctrl+X / F9). The .deb ships the CPU, Vulkan and OSD variants.
install_deb voxtype peteonrails/voxtype "v$VOXTYPE_VERSION" "voxtype_${VOXTYPE_VERSION}-1_amd64.deb"

# Ghostty: Omarchy's default terminal. Ubuntu builds are published by mkasberg/ghostty-ubuntu.
if ! have ghostty; then
  log "ghostty (mkasberg/ghostty-ubuntu latest .deb for 24.04)"
  asset=$(curl -fsSL https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest | grep -oE '"browser_download_url": *"[^"]*24\.04[^"]*amd64\.deb"' | head -1 | cut -d'"' -f4)
  [[ -n $asset ]] || die "could not find a ghostty .deb for 24.04"
  mkdir -p "$DOWNLOADS"
  curl -fsSL -o "$DOWNLOADS/ghostty.deb" "$asset"
  apt-get install -y "$DOWNLOADS/ghostty.deb"
fi
