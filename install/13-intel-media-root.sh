#!/bin/bash
# Hardware video on an Intel GPU that runs on the xe kernel driver (Xe2:
# Lunar Lake, Battlemage, and what comes after), root. noble's libva 2.20 does
# not map the xe driver to iHD and its intel-media-driver 24.1 does not
# initialize on Xe2, so VA-API is gone there: screen recordings fall back to
# the CPU, and Sunshine with them. Upstream's Arch stack drives these chips.
# Intel's route for them on 24.04 is its graphics PPA, which also carries a
# kernel and the compute runtime: the pin takes the media stack from it and
# nothing else. A GPU on i915 keeps noble's stack, which drives it.
#
#   13-intel-media-root.sh          the PPA's media stack, on an Intel GPU on xe
#   13-intel-media-root.sh --undo   the PPA and the pin gone, noble's media stack back
#
# OMARCHY_INTEL_MEDIA=1 takes the PPA's stack whatever the driver; =0 never.
source "${REPO_DIR:?}/lib/common.sh"
need_root

ppa=ppa:kobuk-team/intel-graphics
pin=/etc/apt/preferences.d/omarchy-intel-graphics-media
# The media stack is the pin's first stanza.
read -ra media < <(sed -n 's/^Package: \([^*].*\)$/\1/p' "$REPO_DIR/etc/apt/preferences.d/omarchy-intel-graphics-media" | head -n1)

installed_media() {
  local pkg
  for pkg in "${media[@]}"; do
    apt_installed "$pkg" && echo "$pkg"
  done
}

if [[ ${1:-} == --undo ]]; then
  rm -f "$pin"
  if grep -rqs 'kobuk-team/intel-graphics' /etc/apt/sources.list.d/; then
    log "Intel's graphics PPA removed"
    add-apt-repository -y -r -n "$ppa"
  fi
  apt_retry update -qq
  # Back to the newest version Ubuntu's archive has of each, which apt does
  # not downgrade to on its own.
  back=()
  while read -r pkg; do
    version=$(apt-cache madison "$pkg" | awk -F' *[|] *' 'NR == 1 { print $2 }')
    [[ -z $version ]] || back+=("$pkg=$version")
  done < <(installed_media)
  if (( ${#back[@]} > 0 )); then
    log "noble's media stack: ${back[*]}"
    apt_retry install -y --no-remove --allow-downgrades "${back[@]}"
  fi
  exit 0
fi

xe_intel_gpu() {
  local dev
  for dev in /sys/bus/pci/drivers/xe/0000:*; do
    [[ -e $dev && $(cat "$dev/vendor" 2>/dev/null) == 0x8086 ]] && return 0
  done
  return 1
}
case ${OMARCHY_INTEL_MEDIA:-} in
  0)
    note "OMARCHY_INTEL_MEDIA=0: noble's media stack stays"
    exit 0
    ;;
  1) ;;
  *)
    if ! xe_intel_gpu; then
      note "no Intel GPU on the xe driver: noble's media stack drives it"
      exit 0
    fi
    ;;
esac

log "apt pin: only the media stack from Intel's graphics PPA"
install_file 644 "$pin" <"$REPO_DIR/etc/apt/preferences.d/omarchy-intel-graphics-media"

if ! grep -rqs 'kobuk-team/intel-graphics' /etc/apt/sources.list.d/; then
  log "Intel's graphics PPA"
  # -n: add-apt-repository's own update shrugs off an index it could not
  # fetch; the apt_retry update does not.
  add-apt-repository -y -n "$ppa"
fi
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
note "libva $(dpkg-query -W -f='${Version}' libva2), iHD $(dpkg-query -W -f='${Version}' intel-media-va-driver-non-free)"
