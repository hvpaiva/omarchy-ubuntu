#!/bin/bash
source "${REPO_DIR:?}/lib/common.sh"
need_root

etc=$OMARCHY_PATH/etc
sysd=$OMARCHY_PATH/default/systemd

log "mise: newest package from its apt repository"
DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade mise

log "packages Omarchy's base has and the port lacked: Cantarell (GTK's default font), printer setup, pipewire-jack, qemu-user-static, tldr"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends fonts-cantarell system-config-printer pipewire-jack qemu-user-static tldr

log "systemd-oomd: apps are the kill candidates, not the whole session"
install_file 644 /etc/systemd/user/app.slice.d/10-oomd.conf <"$sysd/user/app.slice.d/10-oomd.conf"
note "user managers read app.slice.d at the next login"

log "sleep hooks: gvfs unmounted before sleep, keyboard backlight off before hibernation"
for h in unmount-fuse keyboard-backlight; do
  install_file 755 "/usr/lib/systemd/system-sleep/$h" <"$sysd/system-sleep/$h"
done

log "docker: containers resolve through the host's resolved, log rotation, no boot blocking"
install -d -m 0755 /etc/docker
if [[ -f /etc/docker/daemon.json ]]; then
  merged=$(jq '.dns //= ["172.17.0.1"] | .bip //= "172.17.0.1/16" | ."log-driver" //= "json-file" | ."log-opts" //= {"max-size": "10m", "max-file": "5"}' /etc/docker/daemon.json)
else
  merged=$(cat "$etc/docker/daemon.json")
fi
install_file 644 /etc/docker/daemon.json <<<"$merged"
install_file 644 /etc/systemd/system/docker.service.d/no-block-boot.conf <"$etc/systemd/system/docker.service.d/no-block-boot.conf"
install_file 644 /etc/systemd/resolved.conf.d/20-docker-dns.conf <"$etc/systemd/resolved.conf.d/20-docker-dns.conf"
systemctl daemon-reload
systemctl try-restart systemd-resolved.service >/dev/null 2>&1 || true
note "docker reads daemon.json at its next restart; restarting it stops the running containers"

if apt_installed cups-browsed; then
  log "cups-browsed: driverless queues only, own user and sandbox (Ubuntu's AppArmor profile already allows the cache dir)"
  install_file 644 /etc/sysusers.d/omarchy-cups-browsed.conf <"$etc/sysusers.d/omarchy-cups-browsed.conf"
  systemd-sysusers omarchy-cups-browsed.conf
  for kv in "CacheDir /var/cache/cups-browsed" "CreateIPPPrinterQueues Driverless" "CreateRemoteCUPSPrinterQueues No"; do
    grep -qE "^${kv%% *}[[:space:]]" /etc/cups/cups-browsed.conf || echo "$kv" >>/etc/cups/cups-browsed.conf
  done
  grep -qE '^SystemGroup .*\bcups-browsed\b' /etc/cups/cups-files.conf || sed -i -E 's/^(SystemGroup .*)$/\1 cups-browsed/' /etc/cups/cups-files.conf
  install_file 644 /etc/systemd/system/cups-browsed.service.d/10-omarchy.conf <"$etc/systemd/system/cups-browsed.service.d/10-omarchy.conf"
  systemctl daemon-reload
  systemctl try-restart cups.service cups-browsed.service >/dev/null 2>&1 || warn "cups-browsed did not restart; see journalctl -u cups-browsed"
fi

log "zram: swap in RAM as upstream; the disk swapfile stays, lower priority, for hibernation"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-zram-generator
install_file 644 /etc/systemd/zram-generator.conf <"$sysd/zram-generator.conf.d/90-omarchy.conf"
install_file 644 /etc/sysctl.d/99-omarchy-sysctl.conf <"$etc/sysctl.d/99-omarchy-sysctl.conf"
install_file 644 /etc/tmpfiles.d/omarchy-zswap.conf <"$etc/tmpfiles.d/omarchy-zswap.conf"
systemctl daemon-reload
if systemctl start systemd-zram-setup@zram0.service >/dev/null 2>&1; then
  sysctl -q --system >/dev/null 2>&1 || true
  note "swap now: $(swapon --show=NAME,SIZE,PRIO --noheadings | tr -s ' ' | tr '\n' ';')"
else
  warn "zram0 did not start; the generator sets it up at the next boot, and 99-omarchy-sysctl.conf applies with it"
fi
