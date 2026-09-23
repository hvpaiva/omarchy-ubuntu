#!/bin/bash
source "${REPO_DIR:?}/lib/common.sh"
need_root

theme_dir=/usr/share/plymouth/themes/omarchy
src=$OMARCHY_PATH/default/plymouth

log "Omarchy's Plymouth theme (the LUKS prompt at boot), Ubuntu's alternatives and initramfs"
install -d -m 0755 -o root -g root "$theme_dir" "$theme_dir/logos"
for f in bullet.png entry.png lock.png logo.png omarchy.plymouth omarchy.script preview-unlock.png progress_bar.png progress_box.png logos/oma.png; do
  install -m 0644 -o root -g root -T "$src/$f" "$theme_dir/$f"
done
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$theme_dir/omarchy.plymouth" 200 >/dev/null
update-alternatives --set default.plymouth "$theme_dir/omarchy.plymouth" >/dev/null
update-initramfs -u >/dev/null 2>&1 || warn "update-initramfs failed; run it by hand"
note "default.plymouth -> $(readlink -f /etc/alternatives/default.plymouth)"
note "Style > Unlock in the menu recolours it per theme (omarchy-plymouth-set-by-theme <name>)"
