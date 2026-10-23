#!/bin/bash
# The denoise config omarchy-audio-input-denoise wrote before node.linger: under
# WirePlumber 0.5 its source is gone after the first restart of WirePlumber
# (the switch from noble's 0.4 to the port's build is one) and stays gone until
# the host starts again. Where the denoise is on, `on` writes the config anew,
# for the microphone it filters, starts the host again and makes its source the
# default once more; where it is off, the next `on` writes the new one.
#
# Pending (75) while the source does not come back: an update run outside the
# session, where pactl reaches no PipeWire.
fragment=${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/omarchy-audio-input-denoise.conf.d/90-denoise.conf
[[ -f $fragment ]] || exit 0
grep -q 'node\.linger' "$fragment" && exit 0
systemctl --user is-enabled --quiet omarchy-audio-input-denoise.service || exit 0
"${PORT_DIR:?}/bin/omarchy-audio-input-denoise" on || exit 75
