#!/bin/bash
# Omarchy's system tweaks that apply on Ubuntu (root). The files come straight
# from the checkout's etc/ tree so they follow upstream; only the admin group
# changes (%wheel -> %sudo). Left out on purpose, see docs/deviations.md:
# Arch boot stack (mkinitcpio, limine, plymouth, sddm), faillock (not in
# Ubuntu's PAM stack), nsswitch (Ubuntu's carries sss). zram, cups-browsed and
# docker need a package or an edit here and live in 58-system-extras-root.sh.
source "${REPO_DIR:?}/lib/common.sh"

etc=$OMARCHY_PATH/etc
# Every upstream file this step copies. `--manifest` prints their hashes (as
# any user) so omarchy-update-ubuntu can tell when upstream changed one.
upstream_files=(
  etc/systemd/logind.conf.d/10-ignore-power-button.conf
  etc/systemd/logind.conf.d/20-inhibit-delay.conf
  etc/systemd/system.conf.d/10-faster-shutdown.conf
  etc/systemd/system.conf.d/20-omarchy-nofile.conf
  etc/systemd/user.conf.d/20-omarchy-nofile.conf
  etc/systemd/system/user@.service.d/10-faster-shutdown.conf
  etc/systemd/oomd.conf.d/10-omarchy.conf
  etc/systemd/system/plocate-updatedb.service.d/ac-only.conf
  etc/systemd/resolved.conf.d/10-disable-multicast.conf
  etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf
  etc/sysctl.d/90-omarchy-file-watchers.conf
  etc/sysctl.d/99-omarchy-sysctl.conf
  etc/modprobe.d/omarchy-usb-autosuspend.conf
  etc/sudoers.d/omarchy-passwd-tries
  etc/sudoers.d/omarchy-tzupdate
  etc/sudoers.d/omarchy-dns
  etc/tmpfiles.d/omarchy-nopasswd-sudo.conf
  etc/xdg/kitty/kitty.conf
  etc/fastfetch/config.jsonc
  etc/mise/conf.d/omarchy.toml
  bin/omarchy-dns
)
if [[ ${1:-} == --manifest ]]; then
  (cd "$OMARCHY_PATH" && sha256sum "${upstream_files[@]}")
  exit 0
fi
need_root

from_upstream() { install_file "$1" "/$2" <"$OMARCHY_PATH/$2"; }

log "logind: power key opens Omarchy's power menu instead of powering off"
from_upstream 644 etc/systemd/logind.conf.d/10-ignore-power-button.conf
from_upstream 644 etc/systemd/logind.conf.d/20-inhibit-delay.conf

log "systemd: faster shutdown, higher open-file limits, oomd tuning"
from_upstream 644 etc/systemd/system.conf.d/10-faster-shutdown.conf
from_upstream 644 etc/systemd/system.conf.d/20-omarchy-nofile.conf
from_upstream 644 etc/systemd/user.conf.d/20-omarchy-nofile.conf
from_upstream 644 etc/systemd/system/user@.service.d/10-faster-shutdown.conf
from_upstream 644 etc/systemd/oomd.conf.d/10-omarchy.conf
if [[ -e /usr/lib/systemd/system/plocate-updatedb.service ]]; then
  from_upstream 644 etc/systemd/system/plocate-updatedb.service.d/ac-only.conf
fi
systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true

log "network: resolved without LLMNR/mDNS, Wi-Fi power save off"
from_upstream 644 etc/systemd/resolved.conf.d/10-disable-multicast.conf
from_upstream 644 etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf

log "kernel: inotify watches, USB autosuspend off"
from_upstream 644 etc/sysctl.d/90-omarchy-file-watchers.conf
from_upstream 644 etc/sysctl.d/99-omarchy-sysctl.conf
from_upstream 644 etc/modprobe.d/omarchy-usb-autosuspend.conf
sysctl -q --system >/dev/null 2>&1 || true

log "sudo: more password tries, passwordless timezone and DNS toggles"
for f in omarchy-passwd-tries omarchy-tzupdate omarchy-dns; do
  staged=$(mktemp)
  sed 's/^%wheel /%sudo /' "$etc/sudoers.d/$f" >"$staged"
  visudo -cf "$staged" >/dev/null
  install_file 440 "/etc/sudoers.d/$f" <"$staged"
  rm -f "$staged"
done
# omarchy-dns elevates by calling /usr/bin/omarchy-dns (the path its sudoers
# rule names), so it needs the same root-owned copy as the browser policy helper.
install -m 0755 -o root -g root -T "$OMARCHY_PATH/bin/omarchy-dns" /usr/bin/omarchy-dns
from_upstream 644 etc/tmpfiles.d/omarchy-nopasswd-sudo.conf

log "ssh: keepalive, and mise shims on PATH for ssh sessions"
install_file 644 /etc/ssh/ssh_config.d/20-omarchy-keepalive.conf <<'EOF'
Host *
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ConnectTimeout 10
EOF
if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  echo 'PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin' >>/etc/security/pam_env.conf
  note "written   /etc/security/pam_env.conf (PATH)"
fi

log "app defaults: kitty, fastfetch, mise"
from_upstream 644 etc/xdg/kitty/kitty.conf
from_upstream 644 etc/fastfetch/config.jsonc
from_upstream 644 etc/mise/conf.d/omarchy.toml

log "icons: Yaru back/forward arrows, as upstream's theme-system step"
mkdir -p /usr/share/icons/Yaru/scalable/actions
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
gtk-update-icon-cache /usr/share/icons/Yaru >/dev/null 2>&1 || true

log "user units Ubuntu enables for everyone and Arch does not"
# foot's server, uwsm's failure monitor and hyprsunset: Omarchy starts
# hyprsunset only from the nightlight toggle and never runs the other two.
systemctl --global disable foot-server.socket foot-server.service fumon.service hyprsunset.service >/dev/null 2>&1 || true

if have ufw && ufw status | grep -q '^Status: active'; then
  log "ufw: LocalSend (53317), as upstream's firewall step"
  ufw allow 53317/udp >/dev/null
  ufw allow 53317/tcp >/dev/null
fi

log "Intel media: VA non-free driver and the oneVPL runtime (upstream's intel-media-driver, vpl-gpu-rt)"
if lspci | grep -iE 'vga|3d|display' | grep -qi intel; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends intel-media-va-driver-non-free libmfx-gen1.2
fi

note "logind, sysctl and modprobe changes apply fully after a reboot"

# Remember what was applied so the updater can tell when upstream changes it.
applied=$REPO_DIR/.applied
install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$applied"
(cd "$OMARCHY_PATH" && sha256sum "${upstream_files[@]}") >"$applied/57-system-tweaks.sha256"
chown "$OMARCHY_USER:$OMARCHY_USER" "$applied/57-system-tweaks.sha256"
