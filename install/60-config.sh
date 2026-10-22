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
for f in bindings input looknfeel monitors; do
  [[ -f $cfg/hypr/$f.lua ]] || install -m 0644 "$OMARCHY_PATH/config/hypr/$f.lua" "$cfg/hypr/$f.lua"
done
for f in xdph.conf hyprsunset.conf; do
  if [[ ! -f $cfg/hypr/$f ]]; then
    install -m 0644 "$OMARCHY_PATH/config/hypr/$f" "$cfg/hypr/$f"
  elif ! cmp -s "$OMARCHY_PATH/config/hypr/$f" "$cfg/hypr/$f"; then
    warn "$cfg/hypr/$f differs from Omarchy's (upstream adds the preview share picker); merge by hand"
  fi
done
verify_status=0
Hyprland --verify-config >/dev/null 2>&1 || verify_status=$?
case $verify_status in
  0) ;;
  139) note "Hyprland --verify-config crashed on its way out (0.56 with 4.5's Lua config); after login, hyprctl configerrors tells" ;;
  *) warn "Hyprland --verify-config failed; check $cfg/hypr/*.lua" ;;
esac

log "Omarchy user config"
mkdir -p "$cfg/omarchy"
[[ -f $cfg/omarchy/shell.json ]] || install -m 0644 "$OMARCHY_PATH/config/omarchy/shell.json" "$cfg/omarchy/shell.json"
for d in hooks extensions; do
  [[ -d $cfg/omarchy/$d ]] || cp -a "$OMARCHY_PATH/config/omarchy/$d" "$cfg/omarchy/$d" 2>/dev/null || true
done

# Only where nothing is there yet: a config that exists is the user's, whatever put it
# there, and a re-run must not swap it for the template (the backup's presence was the
# old marker; once the backup is cleaned up the swap happened again).
log "terminal configs (Omarchy's, where none exists)"
for term in alacritty ghostty foot kitty; do
  [[ -d $OMARCHY_PATH/config/$term ]] || continue
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
# 4.5: upstream's input-method setup seeds fcitx5's profile (the CJK methods,
# the compose key), a VM starts without animations or transparency, the
# portal config and Chromium's native messaging hosts come from the user setup.
if [[ -x $OMARCHY_PATH/bin/omarchy-input-method ]]; then
  omarchy-input-method configure --seed >/dev/null 2>&1 || warn "omarchy-input-method configure --seed failed"
fi
if [[ -x $OMARCHY_PATH/bin/omarchy-hw-vm ]] && omarchy-hw-vm && [[ ! -d $OMARCHY_HOME/.local/state/omarchy/toggles/hypr ]]; then
  mkdir -p "$OMARCHY_HOME/.local/state/omarchy/toggles/hypr"
  cp "$OMARCHY_PATH"/default/hypr/toggles/{no-animations,window-opaque}.lua "$OMARCHY_HOME/.local/state/omarchy/toggles/hypr/"
fi
# Seeded once, as upstream's 1788261467 does: a portals.conf of the user's wins.
portals=$cfg/xdg-desktop-portal
if [[ -f $OMARCHY_PATH/config/xdg-desktop-portal/hyprland-portals.conf &&
  ! -e $portals/hyprland-portals.conf && ! -L $portals/hyprland-portals.conf &&
  ! -e $portals/portals.conf && ! -L $portals/portals.conf ]]; then
  install -Dm644 "$OMARCHY_PATH/config/xdg-desktop-portal/hyprland-portals.conf" "$portals/hyprland-portals.conf"
fi
for host in omarchy-install-chromium-copy-url omarchy-install-chromium-ytdlp; do
  [[ -x $OMARCHY_PATH/bin/$host ]] || continue
  "$host" >/dev/null 2>&1 || warn "$host failed"
done
mkdir -p "$cfg/hyprland-preview-share-picker"
[[ -f $cfg/hyprland-preview-share-picker/config.yaml ]] || cp "$OMARCHY_PATH/config/hyprland-preview-share-picker/config.yaml" "$cfg/hyprland-preview-share-picker/"
sed -i "s#^  command: slurp -f .*#  command: omarchy-share-picker-region#" "$cfg/hyprland-preview-share-picker/config.yaml"
mkdir -p "$cfg/btop/themes"
ln -sfn "$OMARCHY_HOME/.local/state/omarchy/current/theme/btop.theme" "$cfg/btop/themes/current.theme"
[[ -f $cfg/btop/btop.conf ]] && sed -i 's/^color_theme = .*/color_theme = "current"/' "$cfg/btop/btop.conf"
# The uwsm session honours XDG autostart, so Ubuntu's GNOME helpers would start
# too: IBus (im-launch), nm-applet (the shell has a network panel) and
# update-notifier (the shell shows Omarchy's own update notice). Hide them.
for a in "$REPO_DIR"/config/autostart/*.desktop; do
  install -Dm644 "$a" "$cfg/autostart/$(basename "$a")"
done

log "the rest of Omarchy's skel: wireplumber, xournalpp, fcitx environment, fontconfig aliases, gpg keyservers, nautilus extensions"
[[ -d $cfg/wireplumber/wireplumber.conf.d ]] || cp -a "$OMARCHY_PATH/config/wireplumber" "$cfg/wireplumber"
[[ -d $cfg/xournalpp ]] || cp -a "$OMARCHY_PATH/config/xournalpp" "$cfg/xournalpp"
install -Dm644 "$OMARCHY_PATH/default/environment.d/10-omarchy-fcitx.conf" "$cfg/environment.d/10-omarchy-fcitx.conf"
# Upstream puts 50-omarchy.conf in the system conf.d; here it goes to the user's, and noble's
# fontconfig 2.15 then applies its strong assign of monospace before the prepend_first that
# omarchy-font-set writes to fonts.conf, whose test no longer matches: the chosen font never
# wins. The assign block stays out and font-set owns the monospace default instead.
mkdir -p "$cfg/fontconfig/conf.d"
awk '/<match/ { buf = $0; inblk = 1; next }
     inblk { buf = buf "\n" $0; if (/<\/match>/) { inblk = 0; if (!(buf ~ /<string>monospace<\/string>/ && buf ~ /mode="assign"/)) print buf }; next }
     { print }' "$OMARCHY_PATH/default/fontconfig/conf.avail/50-omarchy.conf" >"$cfg/fontconfig/conf.d/50-omarchy.conf"
[[ -f $cfg/fontconfig/fonts.conf ]] || omarchy-font-set "JetBrainsMono Nerd Font" >/dev/null 2>&1 || true
fc-cache -f >/dev/null 2>&1 || true
if [[ ! -f $OMARCHY_HOME/.gnupg/dirmngr.conf ]]; then
  mkdir -p "$OMARCHY_HOME/.gnupg" && chmod 700 "$OMARCHY_HOME/.gnupg"
  cp "$OMARCHY_PATH/default/gpg/dirmngr.conf" "$OMARCHY_HOME/.gnupg/dirmngr.conf"
fi
mkdir -p "$OMARCHY_HOME/.local/share/nautilus-python/extensions"
cp "$OMARCHY_PATH"/default/nautilus-python/extensions/*.py "$OMARCHY_HOME/.local/share/nautilus-python/extensions/"

# Omarchy's mimeapps.list opens text files with nvim.desktop, which Arch's
# neovim package installs. A Neovim from the upstream tarball ships the file
# but installs nothing, so text files would have no handler.
if have nvim && [[ ! -e /usr/share/applications/nvim.desktop && ! -e $OMARCHY_HOME/.local/share/applications/nvim.desktop ]]; then
  nvim_desktop=$(dirname "$(readlink -f "$(command -v nvim)")")/../share/applications/nvim.desktop
  if [[ -f $nvim_desktop ]]; then
    ln -sfn "$(readlink -f "$nvim_desktop")" "$OMARCHY_HOME/.local/share/applications/nvim.desktop"
    update-desktop-database "$OMARCHY_HOME/.local/share/applications" >/dev/null 2>&1 || true
    note "linked    nvim.desktop from the Neovim install"
  fi
fi

log "first theme (headless; the running shell re-applies it after login)"
theme=${OMARCHY_THEME:-tokyo-night}
if [[ ! -f $OMARCHY_HOME/.local/state/omarchy/current/theme.name ]]; then
  OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "$theme"
fi
note "theme $(cat "$OMARCHY_HOME/.local/state/omarchy/current/theme.name")"
# 4.5: fcitx5's profile pointed at Omarchy's theme (upstream's install/user/theme.sh;
# 4.0.6's omarchy-theme-set-fcitx5 has no --activate).
if grep -qs -- '--activate' "$OMARCHY_PATH/bin/omarchy-theme-set-fcitx5"; then
  omarchy-theme-set-fcitx5 --activate >/dev/null 2>&1 || warn "omarchy-theme-set-fcitx5 --activate failed"
fi
# The lazy shims for what /etc/mise/conf.d declares, step 57's (upstream's install/user/mise.sh).
if [[ -f /etc/mise/conf.d/omarchy-tools.toml && -x $LOCAL_BIN/mise ]]; then
  "$LOCAL_BIN/mise" reshim --system >/dev/null 2>&1 || warn "mise reshim --system failed"
  "$LOCAL_BIN/mise" reshim >/dev/null 2>&1 || true
fi
