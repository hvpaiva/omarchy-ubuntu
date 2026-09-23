#!/bin/bash
# Microphone noise suppression: the DeepFilterNet LADSPA plugin, hosted by
# omarchy-audio-input-denoise as its own PipeWire client (see bin/).
source "${REPO_DIR:?}/lib/common.sh"
need_user

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

install -Dm644 "$REPO_DIR/config/systemd/user/omarchy-audio-input-denoise.service" \
  "$OMARCHY_HOME/.config/systemd/user/omarchy-audio-input-denoise.service"
systemctl --user daemon-reload

if [[ -f $OMARCHY_HOME/.config/pipewire/omarchy-audio-input-denoise.conf.d/90-denoise.conf ]]; then
  note "denoise source already configured; omarchy-audio-input-denoise status"
else
  note "enable with: omarchy-audio-input-denoise on"
fi
