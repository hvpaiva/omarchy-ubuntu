#!/bin/bash
# GDM session entries and autologin target (root). Ubuntu keeps GDM; Omarchy's
# SDDM theme needs SDDM 0.21 and noble ships 0.20, so the greeter is the one
# visible deviation from upstream.
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "wayland session entries"
install_file 644 /usr/share/wayland-sessions/omarchy.desktop <"$REPO_DIR/etc/wayland-sessions/omarchy.desktop"
# The packaged `Hyprland` entry (start-hyprland, no uwsm) also loads hyprland.lua
# and stays as the fallback; autostart.lua starts the units by hand there.

log "GDM autologin session -> omarchy (uwsm), upstream's session model"
accounts=/var/lib/AccountsService/users/$OMARCHY_USER
if [[ -f $accounts ]]; then
  if grep -q '^Session=' "$accounts"; then
    sed -i 's/^Session=.*/Session=omarchy/' "$accounts"
  else
    printf '\n[User]\nSession=omarchy\n' >>"$accounts"
  fi
  note "$(grep '^Session=' "$accounts") in $accounts"
else
  note "no AccountsService record yet; pick 'Omarchy (Hyprland uwsm)' once in the greeter"
fi
