#!/bin/bash
# Tools that Ubuntu does not package: official .deb releases, pinned in
# versions.env. Root (dpkg). `--outdated` lists, as any user, the ones whose
# installed version is not the pinned one, for omarchy-update-ubuntu;
# `--release` reinstalls the ones built per Ubuntu release.
source "${REPO_DIR:?}/lib/common.sh"

# name, GitHub repository, release tag, asset, the version dpkg then reports.
#   gum: the TUI toolkit every omarchy-* prompt uses.
#   fastfetch: Omarchy's system summary; noble has no package.
#   LocalSend: the Super+Ctrl+S share menu (`localsend --headless send`).
#   Voxtype: dictation (Super+Ctrl+X / F9); the .deb ships the CPU, Vulkan and OSD variants.
#   Ghostty: Omarchy's default terminal, in mkasberg/ghostty-ubuntu's build for
#     this Ubuntu release; its revision is -ppa2 in the tag, .ppa2 in the asset
#     and ~ppa2 in dpkg.
#   Aether: the theming app. Omarchy's own package installs the release binary
#   rather than building it; the release also ships a .deb, built on Ubuntu 24.04.
debs() {
  cat <<EOF
gum charmbracelet/gum v$GUM_VERSION gum_${GUM_VERSION}_amd64.deb $GUM_VERSION
fastfetch fastfetch-cli/fastfetch $FASTFETCH_VERSION fastfetch-linux-amd64.deb $FASTFETCH_VERSION
localsend localsend/localsend v$LOCALSEND_VERSION LocalSend-${LOCALSEND_VERSION}-linux-x86-64.deb $LOCALSEND_VERSION
voxtype peteonrails/voxtype v$VOXTYPE_VERSION voxtype_${VOXTYPE_VERSION}-1_amd64.deb $VOXTYPE_VERSION
ghostty mkasberg/ghostty-ubuntu ${GHOSTTY_DEB/.ppa/-ppa} ghostty_${GHOSTTY_DEB}_amd64_${UBUNTU_VERSION}.deb ${GHOSTTY_DEB/.ppa/\~ppa}
EOF
  # One of upstream's preinstalls: omarchy-remove-preinstalls drops it and leaves
  # this marker, and no update of upstream's brings a dropped one back.
  [[ -f $OMARCHY_HOME/.local/state/omarchy/preinstalls-removed ]] ||
    echo "aether omacom/aether $AETHER_VERSION aether_${AETHER_VERSION#v}_amd64.deb ${AETHER_VERSION#v}"
}

at_pin() { # at_pin <name> <version>: the package is installed at the pinned version (a Debian revision or build number aside)
  local installed
  # dpkg-query still answers for a package removed but not purged.
  apt_installed "$1" || return 1
  installed=$(dpkg-query -W -f='${Version}' "$1" 2>/dev/null) || return 1
  [[ $installed == "$2" || $installed == "$2"[-+]* ]]
}

if [[ ${1:-} == --outdated ]]; then
  while read -r name _ _ _ version; do
    at_pin "$name" "$version" || echo "$name"
  done < <(debs)
  exit 0
fi
need_root

# --release (after a release upgrade): the .debs built for one Ubuntu release,
# named after it, again at their pins, as the new release's build.
for_release=0
[[ ${1:-} != --release ]] || for_release=1

install_deb() { # install_deb <name> <github repo> <tag> <asset> <version>
  local name=$1 repo=$2 tag=$3 asset=$4 version=$5 again=()
  if at_pin "$name" "$version"; then
    if (( for_release )) && [[ $asset == *"_$UBUNTU_VERSION.deb" ]]; then
      again=(--reinstall)
    else
      note "unchanged $name $version"
      return
    fi
  fi
  log "$name $version from $repo $tag"
  # An asset named without its version (fastfetch's) would otherwise come back
  # from the cache at the old one.
  rm -f "$DOWNLOADS/$asset"
  su -s /bin/bash "$OMARCHY_USER" -c "REPO_DIR='$REPO_DIR'; source '$REPO_DIR/lib/common.sh'; github_release_download '$repo' '$tag' '$asset'"
  # The .deb is local; what it depends on comes through apt, the PPAs included.
  apt_retry install -y --allow-downgrades "${again[@]}" "$DOWNLOADS/$asset"
}

while read -r name repo tag asset version; do
  install_deb "$name" "$repo" "$tag" "$asset" "$version"
done < <(debs)

# The LocalSend .deb only installs /opt/localsend_app/localsend_app; the Arch
# package puts `localsend` on PATH.
ln -sfn /opt/localsend_app/localsend_app /usr/local/bin/localsend
