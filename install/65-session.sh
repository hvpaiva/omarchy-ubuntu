#!/bin/bash
# Session cutover (user side): Omarchy's user units, the old stack out of the way,
# migrations marked as shipped, first-run provisioning.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export PATH="$OMARCHY_PATH/bin:$LOCAL_BIN:$PATH"
export OMARCHY_PATH
units_src=$OMARCHY_PATH/default/systemd/user
units_dst=$OMARCHY_HOME/.config/systemd/user
mkdir -p "$units_dst"

log "old stack out of autostart (waybar, walker, elephant, mako, swayosd, hyprpolkitagent)"
for u in elephant.service swayosd.service; do
  systemctl --user disable "$u" >/dev/null 2>&1 || true
done
# Units their packages enable in global scope (WantedBy=graphical-session.target)
# would come back with the uwsm session: waybar next to the shell's bar, hypridle
# fighting the shell's idle, hyprpolkitagent registering before the shell's agent,
# mako and swaync both claiming org.freedesktop.Notifications. Mask them.
systemctl --user mask mako.service swaync.service waybar.service hypridle.service hyprpolkitagent.service >/dev/null 2>&1 || true
mkdir -p "$OMARCHY_HOME/.config/autostart.disabled-omarchy"
for d in walker.desktop ulauncher.desktop; do
  [[ -f $OMARCHY_HOME/.config/autostart/$d ]] && mv "$OMARCHY_HOME/.config/autostart/$d" "$OMARCHY_HOME/.config/autostart.disabled-omarchy/$d"
done

log "Omarchy user units (ExecStart rewritten to the checkout)"
# WantedBy=graphical-session.target: pulled in by the uwsm session; the direct
# GDM entry never activates that target, so autostart.lua also starts them.
units="bt-agent.service omarchy-sleep-lock.service omarchy-crash-watch.service omarchy-recover-internal-monitor.service omarchy-tailscale-receive.service omarchy-migrate-notify.service omarchy-fcitx5.service"
for u in $units; do
  rewrite_unit "$units_src/$u" "$units_dst/$u"
done
systemctl --user daemon-reload
# shellcheck disable=SC2086
systemctl --user enable $units >/dev/null 2>&1

log "migrations: mark everything shipped with this tag as done (a fresh install's state)"
# Otherwise omarchy-migrate would run every migration ever shipped, several of
# them through pacman. Only migrations newer than the checkout stay pending.
mkdir -p "$OMARCHY_HOME/.local/state/omarchy/migrations"
for m in "$OMARCHY_PATH"/migrations/*.sh; do
  touch "$OMARCHY_HOME/.local/state/omarchy/migrations/$(basename "$m")"
done

log "first-run provisioning (hooks, GNOME theme, welcome and update notifications)"
if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  omarchy-provision-first-run >/dev/null 2>&1 || warn "first-run reported a failed step; see ~/.local/state/omarchy/first-run.log"
else
  note "no Wayland session: first-run will run at the first login"
fi

log "applications and web apps (Omarchy's .desktop entries; mise-managed CLIs)"
omarchy-refresh-applications >/dev/null 2>&1 || warn "omarchy-refresh-applications failed"

if have voxtype && [[ ! -f $OMARCHY_HOME/.config/voxtype/config.toml ]]; then
  log "voxtype: config, model, user unit (upstream's omarchy-voxtype-install without the prompt)"
  mkdir -p "$OMARCHY_HOME/.config/voxtype"
  cp "$OMARCHY_PATH/default/voxtype/config.toml" "$OMARCHY_HOME/.config/voxtype/"
  voxtype setup --download --no-post-install
  voxtype setup systemd
fi
