#!/bin/bash
# Microphone noise suppression: the DeepFilterNet LADSPA plugin, hosted by
# omarchy-audio-input-denoise as its own PipeWire client (see bin/). With
# --units, only the user units, which the updater keeps current.
source "${REPO_DIR:?}/lib/common.sh"
need_user

# WirePlumber, where noble's 0.4 is the system's: step 45's 0.5 in its place,
# through a drop-in, and the running session moves to it at once. Without that
# build, a drop-in for 0.4, which holds back all of its linking while any node
# it manages has not finished activating: a filter-chain host (upstream's
# speaker tuning, the denoise here) whose nodes outlive a WirePlumber restart
# can leave one that never does, and then no stream on the machine is linked.
# That drop-in restarts the hosts after WirePlumber, as at login.
units() {
  local dir=$OMARCHY_HOME/.config/systemd/user changed=0 switched=0 file
  local filters=wireplumber.service.d/10-omarchy-filter-chains.conf
  local wp05=wireplumber.service.d/20-omarchy-wireplumber-0.5.conf
  local files=(omarchy-audio-input-denoise.service) gone
  if [[ $(/usr/bin/wireplumber --version 2>/dev/null) != *"libwireplumber 0.4."* ]]; then
    gone=("$filters" "$wp05")
  elif [[ -x /usr/local/bin/wireplumber ]]; then
    files+=("$wp05")
    gone=("$filters")
  else
    files+=("$filters")
    gone=("$wp05")
  fi
  for file in "${gone[@]}"; do
    [[ -e $dir/$file ]] || continue
    rm -f "$dir/$file"
    note "unit removed: $file"
    changed=1
  done
  for file in "${files[@]}"; do
    cmp -s "$REPO_DIR/config/systemd/user/$file" "$dir/$file" && continue
    install -Dm644 "$REPO_DIR/config/systemd/user/$file" "$dir/$file"
    note "unit updated: $file"
    changed=1
    [[ $file != "$wp05" ]] || switched=1
  done
  (( changed == 0 )) || systemctl --user daemon-reload
  (( switched == 0 )) || systemctl --user try-restart wireplumber.service
}
if [[ ${1:-} == --units ]]; then
  units
  exit 0
fi

asset="libdeep_filter_ladspa-$DEEPFILTER_VERSION-x86_64-unknown-linux-gnu.so"
plugin="$OMARCHY_HOME/.local/lib/ladspa/libdeep_filter_ladspa.so"

if [[ -f $plugin ]] && sha256sum "$plugin" | grep -q "^$DEEPFILTER_SHA256 "; then
  note "unchanged DeepFilterNet $DEEPFILTER_VERSION"
else
  log "DeepFilterNet LADSPA plugin $DEEPFILTER_VERSION"
  github_release_download Rikorose/DeepFilterNet "v$DEEPFILTER_VERSION" "$asset"
  sha256sum "$DOWNLOADS/$asset" | grep -q "^$DEEPFILTER_SHA256 " || die "$asset: checksum mismatch"
  install -Dm644 "$DOWNLOADS/$asset" "$plugin"
fi

units

if [[ -f $OMARCHY_HOME/.config/pipewire/omarchy-audio-input-denoise.conf.d/90-denoise.conf ]]; then
  note "denoise source already configured; omarchy-audio-input-denoise status"
else
  note "enable with: omarchy-audio-input-denoise on"
fi
