#!/bin/bash
# The denoise config omarchy-audio-input-denoise wrote with node.dont-fallback:
# WirePlumber 0.5 destroys its capture at the first restart of WirePlumber
# (the switch from noble's 0.4 to the port's build is one), and the source
# stays gone until the host starts again. Where the denoise is on, `on` writes
# the config anew, for the microphone it filters, starts the host again and
# makes its source the default once more; where it is off, the next `on`
# writes the new one.
#
# Pending (75) until `on` succeeds, or while the user's systemd is out of
# reach: an update run outside the desktop session.
fragment=${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/omarchy-audio-input-denoise.conf.d/90-denoise.conf
[[ -f $fragment ]] || exit 0
state=$(systemctl --user is-enabled omarchy-audio-input-denoise.service 2>/dev/null) || true
case $state in
  enabled) ;;
  "") exit 75 ;;
  *) exit 0 ;;
esac
"${PORT_DIR:?}/bin/omarchy-audio-input-denoise" on || exit 75
