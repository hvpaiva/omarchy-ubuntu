#!/bin/bash
# 4.5 starts owed with the session. The direct GDM entry starts Omarchy's user
# units only through the list in autostart.lua, which step 60 copies once, so
# a file from before 4.5 needs the name added.
#
# Pending (75) until the checkout carries owe's migration: 4.5 and later.
[[ -f ${OMARCHY_PATH:?}/migrations/1789764927.sh ]] || exit 75
autostart=$HOME/.config/hypr/autostart.lua
[[ -f $autostart ]] || exit 0
grep -q 'owed\.service' "$autostart" && exit 0
sed -i 's/\(\.\. " voxtype\.service\)\([ "]\)/\1 owed.service\2/' "$autostart"
# An edited list the pattern does not reach stays the user's to extend.
if ! grep -q 'owed\.service' "$autostart"; then
  echo "autostart.lua: add owed.service to the systemctl --user start list (the packaged Hyprland entry starts units only from there)" >&2
  exit 75
fi
