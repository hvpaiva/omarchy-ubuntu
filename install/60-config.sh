#!/bin/bash
# User configuration: Hyprland Lua config, Omarchy config dirs, terminal configs,
# fcitx5, the share picker, the first theme. Existing personal files are backed
# up once and never overwritten on later runs.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export PATH="$OMARCHY_PATH/bin:$LOCAL_BIN:$PATH"
export OMARCHY_PATH
cfg=$OMARCHY_HOME/.config

log "Hyprland config (Lua, Omarchy layout)"
mkdir -p "$cfg/hypr"
if ls "$cfg"/hypr/*.conf >/dev/null 2>&1 && [[ ! -d $cfg/hypr.bak-omarchy ]]; then
  cp -a "$cfg/hypr" "$cfg/hypr.bak-omarchy"
  note "backup    $cfg/hypr.bak-omarchy (old .conf stack kept for the legacy session entry)"
fi
# hyprland.lua and autostart.lua carry the Ubuntu glue and are managed by the repo.
for f in hyprland autostart; do
  if ! cmp -s "$REPO_DIR/config/hypr/$f.lua" "$cfg/hypr/$f.lua"; then
    backup_once "$cfg/hypr/$f.lua"
    install -m 0644 "$REPO_DIR/config/hypr/$f.lua" "$cfg/hypr/$f.lua"
    note "written   $cfg/hypr/$f.lua"
  fi
done
# The rest is personal: seeded from upstream's stubs only when absent.
for f in bindings input looknfeel; do
  [[ -f $cfg/hypr/$f.lua ]] || install -m 0644 "$OMARCHY_PATH/config/hypr/$f.lua" "$cfg/hypr/$f.lua"
done
[[ -f $cfg/hypr/monitors.lua ]] || install -m 0644 "$REPO_DIR/config/hypr/monitors.lua.example" "$cfg/hypr/monitors.lua"
for f in xdph.conf hyprsunset.conf; do
  if [[ ! -f $cfg/hypr/$f ]]; then
    install -m 0644 "$OMARCHY_PATH/config/hypr/$f" "$cfg/hypr/$f"
  elif ! cmp -s "$OMARCHY_PATH/config/hypr/$f" "$cfg/hypr/$f"; then
    warn "$cfg/hypr/$f differs from Omarchy's (upstream adds the preview share picker); merge by hand"
  fi
done
Hyprland --verify-config >/dev/null 2>&1 || warn "Hyprland --verify-config failed; check $cfg/hypr/*.lua"

log "Omarchy user config"
mkdir -p "$cfg/omarchy"
[[ -f $cfg/omarchy/shell.json ]] || install -m 0644 "$OMARCHY_PATH/config/omarchy/shell.json" "$cfg/omarchy/shell.json"
for d in hooks extensions; do
  [[ -d $cfg/omarchy/$d ]] || cp -a "$OMARCHY_PATH/config/omarchy/$d" "$cfg/omarchy/$d" 2>/dev/null || true
done

log "terminal configs (Omarchy's; yours are backed up once)"
for term in alacritty ghostty foot kitty; do
  [[ -d $OMARCHY_PATH/config/$term ]] || continue
  if [[ -e $cfg/$term && ! -e $cfg/$term.bak-omarchy ]]; then
    mv "$cfg/$term" "$cfg/$term.bak-omarchy"
    note "backup    $cfg/$term.bak-omarchy"
  fi
  [[ -e $cfg/$term ]] || cp -a "$OMARCHY_PATH/config/$term" "$cfg/$term"
done
[[ -f $cfg/xdg-terminals.list ]] || printf 'com.mitchellh.ghostty.desktop\n' >"$cfg/xdg-terminals.list"

log "fcitx5 (XCompose sequences), share picker, btop theme hook, IBus autostart hidden"
[[ -d $cfg/fcitx5 ]] || cp -a "$OMARCHY_PATH/config/fcitx5" "$cfg/fcitx5"
if ! grep -q wayland-diagnose-other "$cfg/fcitx5/conf/notifications.conf" 2>/dev/null; then
  fcitx_was_active=$(systemctl --user is-active omarchy-fcitx5.service 2>/dev/null)
  systemctl --user stop omarchy-fcitx5.service >/dev/null 2>&1 || true
  printf '# Hidden Notifications\n[HiddenNotifications]\n0=wayland-diagnose-other\n' >"$cfg/fcitx5/conf/notifications.conf"
  [[ $fcitx_was_active == active ]] && systemctl --user start omarchy-fcitx5.service >/dev/null 2>&1 || true
fi
mkdir -p "$cfg/hyprland-preview-share-picker"
[[ -f $cfg/hyprland-preview-share-picker/config.yaml ]] || cp "$OMARCHY_PATH/config/hyprland-preview-share-picker/config.yaml" "$cfg/hyprland-preview-share-picker/"
mkdir -p "$cfg/btop/themes"
ln -sfn "$OMARCHY_HOME/.local/state/omarchy/current/theme/btop.theme" "$cfg/btop/themes/current.theme"
[[ -f $cfg/btop/btop.conf ]] && sed -i 's/^color_theme = .*/color_theme = "current"/' "$cfg/btop/btop.conf"
# The uwsm session honours XDG autostart, so Ubuntu's GNOME helpers would start
# too: IBus (im-launch), nm-applet (the shell has a network panel) and
# update-notifier (the shell shows Omarchy's own update notice). Hide them.
for a in im-launch nm-applet update-notifier; do
  install -Dm644 "$REPO_DIR/config/autostart/$a.desktop" "$cfg/autostart/$a.desktop"
done

log "the rest of Omarchy's skel: wireplumber, xournalpp, fcitx environment, fontconfig aliases, gpg keyservers, nautilus extensions"
[[ -d $cfg/wireplumber/wireplumber.conf.d ]] || cp -a "$OMARCHY_PATH/config/wireplumber" "$cfg/wireplumber"
[[ -d $cfg/xournalpp ]] || cp -a "$OMARCHY_PATH/config/xournalpp" "$cfg/xournalpp"
install -Dm644 "$OMARCHY_PATH/default/environment.d/10-omarchy-fcitx.conf" "$cfg/environment.d/10-omarchy-fcitx.conf"
install -Dm644 "$OMARCHY_PATH/default/fontconfig/conf.avail/50-omarchy.conf" "$cfg/fontconfig/conf.d/50-omarchy.conf"
fc-cache -f >/dev/null 2>&1 || true
if [[ ! -f $OMARCHY_HOME/.gnupg/dirmngr.conf ]]; then
  mkdir -p "$OMARCHY_HOME/.gnupg" && chmod 700 "$OMARCHY_HOME/.gnupg"
  cp "$OMARCHY_PATH/default/gpg/dirmngr.conf" "$OMARCHY_HOME/.gnupg/dirmngr.conf"
fi
mkdir -p "$OMARCHY_HOME/.local/share/nautilus-python/extensions"
cp "$OMARCHY_PATH"/default/nautilus-python/extensions/*.py "$OMARCHY_HOME/.local/share/nautilus-python/extensions/"

log "first theme (headless; the running shell re-applies it after login)"
theme=${OMARCHY_THEME:-tokyo-night}
if [[ ! -f $OMARCHY_HOME/.local/state/omarchy/current/theme.name ]]; then
  OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "$theme"
fi
note "theme $(cat "$OMARCHY_HOME/.local/state/omarchy/current/theme.name")"
