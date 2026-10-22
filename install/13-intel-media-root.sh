#!/bin/bash
# Hardware video on an Intel GPU that runs on the xe kernel driver (Xe2:
# Lunar Lake, Battlemage, and what comes after), root. noble's libva 2.20 does
# not map the xe driver to iHD and its intel-media-driver 24.1 does not
# initialize on Xe2, so VA-API is gone there: screen recordings fall back to
# the CPU, and Sunshine with them. Upstream's Arch stack drives these chips.
# Intel's route for them on 24.04 is its graphics PPA, which also carries a
# kernel and the compute runtime: the pin takes the media stack from it and
# nothing else. A GPU on i915 keeps noble's stack, which drives it. 26.04's
# own stack drives xe (libva 2.24, iHD 26.3): there the step only retires the
# PPA an install on noble took, back to the archive's.
#
#   13-intel-media-root.sh          the PPA's media stack, on an Intel GPU on xe
#   13-intel-media-root.sh --undo   the PPA and the pin gone, the archive's media stack back
#   13-intel-media-root.sh --due    (as the user) whether the updater runs the step
#
# OMARCHY_INTEL_MEDIA=1 takes the PPA's stack whatever the driver and the
# release; =0 never. A machine bootstrapped before the step takes it at its
# next update. --undo and =0 leave a marker in .applied, so the updates after
# them keep the archive's.
source "${REPO_DIR:?}/lib/common.sh"

ppa=kobuk-team/intel-graphics
pin=/etc/apt/preferences.d/omarchy-intel-graphics-media
declined=$REPO_DIR/.applied/13-intel-media-declined
# The media stack is the pin's first stanza.
read -ra media < <(sed -n 's/^Package: \([^*].*\)$/\1/p' "$REPO_DIR/etc/apt/preferences.d/omarchy-intel-graphics-media" | head -n1)

xe_intel_gpu() {
  local dev
  for dev in /sys/bus/pci/drivers/xe/0000:*; do
    [[ -e $dev && $(cat "$dev/vendor" 2>/dev/null) == 0x8086 ]] && return 0
  done
  return 1
}

archive_version() { # the newest version of a package in Ubuntu's archive, the PPA's aside
  apt-cache madison "$1" 2>/dev/null | awk -F' *[|] *' -v ppa="$ppa" '!found && index($3, ppa) == 0 { print $2; found = 1 }'
}

# The archive's own stack drives xe when libva maps the driver to iHD (2.21)
# and iHD initializes on Xe2 and Xe3 (25.1). The free build of iHD is in
# universe, where the non-free one's multiverse may be off.
archive_drives_xe() {
  local libva ihd
  libva=$(archive_version libva2)
  ihd=$(archive_version intel-media-va-driver)
  [[ -n $libva && -n $ihd ]] && dpkg --compare-versions "$libva" ge 2.21 && dpkg --compare-versions "$ihd" ge 25.1
}

if [[ ${1:-} == --due ]]; then
  [[ ! -f $declined && ${OMARCHY_INTEL_MEDIA:-} != 0 ]] || exit 1
  if [[ ${OMARCHY_INTEL_MEDIA:-} != 1 ]] && archive_drives_xe; then
    [[ -f $pin ]] && exit 0
    exit 1
  fi
  [[ ! -f $pin ]] || exit 1
  [[ ${OMARCHY_INTEL_MEDIA:-} == 1 ]] || xe_intel_gpu || exit 1
  exit 0
fi
need_root

installed_media() {
  local pkg
  for pkg in "${media[@]}"; do
    apt_installed "$pkg" && echo "$pkg"
  done
}

decline() {
  install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$REPO_DIR/.applied"
  install -m 644 -o "$OMARCHY_USER" -g "$OMARCHY_USER" /dev/null "$declined"
}

retire_ppa() {
  rm -f "$pin"
  if apt_source_active "https://ppa.launchpadcontent.net/$ppa/ubuntu" "$UBUNTU_CODENAME"; then
    log "Intel's graphics PPA removed"
    add-apt-repository -y -r -n "ppa:$ppa"
  fi
  apt_retry update -qq
  # Back to the newest version Ubuntu's archive has of each, which apt does
  # not downgrade to on its own.
  back=()
  while read -r pkg; do
    version=$(archive_version "$pkg")
    [[ -z $version ]] || back+=("$pkg=$version")
  done < <(installed_media)
  if (( ${#back[@]} > 0 )); then
    log "Ubuntu $UBUNTU_VERSION's media stack: ${back[*]}"
    apt_retry install -y --no-remove --allow-downgrades "${back[@]}"
  fi
}

if [[ ${1:-} == --undo ]]; then
  retire_ppa
  decline
  exit 0
fi

case ${OMARCHY_INTEL_MEDIA:-} in
  0)
    note "OMARCHY_INTEL_MEDIA=0: Ubuntu's media stack stays"
    decline
    exit 0
    ;;
  1) ;;
  *)
    if archive_drives_xe; then
      if [[ -f $pin ]]; then
        log "Ubuntu $UBUNTU_VERSION's own media stack drives the xe driver: Intel's PPA retired"
        retire_ppa
      else
        note "Ubuntu $UBUNTU_VERSION's own media stack drives the xe driver"
      fi
      exit 0
    fi
    if ! xe_intel_gpu; then
      note "no Intel GPU on the xe driver: Ubuntu's media stack drives it"
      exit 0
    fi
    ;;
esac

log "apt pin: only the media stack from Intel's graphics PPA"
install_file 644 "$pin" <"$REPO_DIR/etc/apt/preferences.d/omarchy-intel-graphics-media"

log "Intel's graphics PPA"
ppa_source "$ppa"
apt_retry update -qq

# The pin must hold: an upgrade may take only the media stack from the PPA.
if LC_ALL=C apt-get -s dist-upgrade | grep '^Inst ' | grep 'intel-graphics' | grep -vqE "^Inst ($(IFS='|'; echo "${media[*]}")) "; then
  LC_ALL=C apt-get -s dist-upgrade | grep '^Inst ' | grep 'intel-graphics' >&2
  die "the pin is not holding: an upgrade would pull the packages above from Intel's PPA"
fi

# The driver and the libraries VA-API loads it through, plus every package of
# the stack already here, which moves with libva (libva-dev, from step 10, among
# them).
mapfile -t here < <(installed_media)
log "the PPA's media stack"
apt_retry install -y --no-remove intel-media-va-driver-non-free libva2 libva-drm2 libva-wayland2 libvpl2 libmfx-gen1.2 vainfo "${here[@]}"
rm -f "$declined"
note "libva $(dpkg-query -W -f='${Version}' libva2), iHD $(dpkg-query -W -f='${Version}' intel-media-va-driver-non-free)"
