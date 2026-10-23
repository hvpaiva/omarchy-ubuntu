#!/bin/bash
# The session entries and the display manager (root). Upstream's login screen
# is SDDM with Omarchy's theme, a Qt 6 greeter that SDDM runs from 0.21 on:
# where the release packages that (26.04), SDDM becomes the display manager
# as Omarchy's settings package and installer set it up. noble packages 0.20,
# so GDM stays there. GDM stays installed either way: removing it takes
# ubuntu-desktop with it.
#
#   66-session-root.sh          the session entries; SDDM where the release's runs the theme
#   66-session-root.sh --undo   GDM the display manager again, and kept at the updates after
#   66-session-root.sh --due    (as the user) whether the updater runs the step
#
# The switch counts from the next boot: the display manager under the running
# session is never restarted. Once set up, the updates keep SDDM's files at
# upstream's while SDDM is the display manager; a GDM chosen back, through
# --undo or by hand, stays. A plain run of the step takes SDDM again.
source "${REPO_DIR:?}/lib/common.sh"

declined=$REPO_DIR/.applied/66-sddm-declined
applied=$REPO_DIR/.applied/66-sddm.sha256
theme=/usr/share/sddm/themes/omarchy
# What Omarchy's settings package installs for SDDM, from the checkout.
config_files=(etc/sddm.conf.d/10-theme.conf etc/sddm.conf.d/10-wayland.conf)

# The theme's metadata asks for the Qt 6 greeter, which SDDM has from 0.21.
sddm_runs_theme() {
  local candidate
  candidate=$(apt_candidate sddm)
  [[ -n $candidate ]] && dpkg --compare-versions "$candidate" ge 0.21
}

# The display manager as the Debian packages read it, the name of the daemon
# in /etc/X11/default-display-manager.
display_manager() {
  local daemon
  daemon=$(grep -v '^[[:space:]]*#' /etc/X11/default-display-manager 2>/dev/null | head -n1) || true
  [[ -z $daemon ]] || basename "$daemon"
}

manifest() {
  (cd "$OMARCHY_PATH" && { printf '%s\n' "${config_files[@]}"; find default/sddm -type f | LC_ALL=C sort; } | xargs -r sha256sum)
}

dm_unit=/etc/systemd/system/display-manager.service
# An admin's mask, which the display managers' maintainer scripts leave too.
dm_masked() { [[ $(readlink "$dm_unit" 2>/dev/null) == /dev/null ]]; }

if [[ ${1:-} == --due ]]; then
  [[ ! -f $declined ]] && sddm_runs_theme || exit 1
  ! dm_masked || exit 1
  [[ -f $applied ]] || exit 0
  [[ $(display_manager) == sddm ]] && ! manifest | cmp -s - "$applied"
  exit
fi
need_root

decline() {
  install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$REPO_DIR/.applied"
  install -m 644 -o "$OMARCHY_USER" -g "$OMARCHY_USER" /dev/null "$declined"
}

# What the display managers' own maintainer scripts do with the choice:
# debconf's shared answer, display-manager.service (the alias both units
# claim), and the daemon in /etc/X11/default-display-manager. A later upgrade
# of either package reads the file and links the unit after it, so the file
# goes last: a run cut short before it leaves the switch still to do.
make_display_manager() { # make_display_manager <package> <daemon>
  echo "$1 shared/default-x-display-manager select $1" | debconf-set-selections
  dm_masked || ln -sf "/lib/systemd/system/$1.service" "$dm_unit"
  printf '%s\n' "$2" >/etc/X11/default-display-manager
}

if [[ ${1:-} == --undo ]]; then
  [[ -x /usr/sbin/gdm3 ]] || die "gdm3 is not installed: apt install gdm3, then this again"
  if [[ $(display_manager) != gdm3 || $(readlink "$dm_unit" 2>/dev/null) != /lib/systemd/system/gdm3.service ]]; then
    log "GDM the display manager again, from the next boot"
    make_display_manager gdm3 /usr/sbin/gdm3
  fi
  decline
  note "the updates keep GDM; $REPO_DIR/bootstrap.sh 66 takes SDDM again"
  exit 0
fi

log "wayland session entries"
install_file 644 /usr/share/wayland-sessions/omarchy.desktop <"$REPO_DIR/etc/wayland-sessions/omarchy.desktop"
# The packaged `Hyprland` entry (start-hyprland, no uwsm) also loads hyprland.lua
# and stays as the fallback; autostart.lua starts the units by hand there.

# Also what a GDM chosen back over SDDM logs in to.
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

if ! sddm_runs_theme; then
  candidate=$(apt_candidate sddm)
  note "Omarchy's theme needs SDDM 0.21, Ubuntu $UBUNTU_VERSION offers ${candidate:-none}: GDM stays the display manager"
  exit 0
fi

# GDM's automatic login, for SDDM's: the port has no installer to ask, so the
# machine keeps what its owner chose there.
gdm_autologin_user() {
  awk -F= '
    /^[[:space:]]*\[/ { daemon = ($0 ~ /^[[:space:]]*\[daemon\]/) }
    daemon { key = $1; gsub(/[[:space:]]/, "", key); value = $2; gsub(/[[:space:]]/, "", value) }
    daemon && key == "AutomaticLoginEnable" { enable = tolower(value) }
    daemon && key == "AutomaticLogin" { user = value }
    END { if ((enable == "true" || enable == "1") && user != "") print user }
  ' /etc/gdm3/custom.conf 2>/dev/null
}

switching=0
if dm_masked; then
  note "display-manager.service is masked: the display manager stays as it is"
elif [[ $(display_manager) != sddm || $(readlink "$dm_unit" 2>/dev/null) != /lib/systemd/system/sddm.service ]]; then
  switching=1
fi

log "SDDM with Omarchy's theme and its Hyprland greeter"
# The greeter needs the package's own depends and Qt's Wayland platform plugin
# (upstream's base set carries qt6-wayland); the recommends are another theme,
# Qt Multimedia and the virtual keyboard.
missing=()
for pkg in sddm qt6-wayland; do
  apt_installed "$pkg" || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
  apt_retry install -y --no-install-recommends "${missing[@]}"
fi
for f in "${config_files[@]}"; do
  install_file 644 "/$f" <"$OMARCHY_PATH/$f"
done
# Copies, as the package's: the greeter runs as the sddm user, which cannot
# read the checkout in the user's home, and omarchy-plymouth-set (Style >
# Unlock) refuses a theme directory or file that is a link.
install_file 644 /usr/share/sddm/hyprland.lua <"$OMARCHY_PATH/default/sddm/hyprland.lua"
install -d -m 0755 -o root -g root "$theme"
while IFS= read -r f; do
  install_file 644 "$theme/$f" <"$OMARCHY_PATH/default/sddm/omarchy/$f"
done < <(cd "$OMARCHY_PATH/default/sddm/omarchy" && find . -type f -printf '%P\n' | LC_ALL=C sort)
# What upstream no longer ships goes, as a package upgrade takes it.
while IFS= read -r f; do
  [[ -f $OMARCHY_PATH/default/sddm/omarchy/$f ]] && continue
  rm -f "$theme/$f"
  note "removed   $theme/$f (not upstream's any more)"
done < <(cd "$theme" && find . -type f -printf '%P\n')
# Upstream's login/sddm.sh: a password login must not create an encrypted
# login keyring beside Omarchy's passwordless default one.
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi

if (( switching )); then
  user=$(gdm_autologin_user)
  if [[ -n $user ]] && getent passwd "$user" >/dev/null && [[ $user =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    log "GDM's automatic login for $user, now SDDM's"
    printf '[Autologin]\nUser=%s\nSession=omarchy.desktop\n' "$user" | install_file 644 /etc/sddm.conf.d/autologin.conf
  elif [[ -e /etc/sddm.conf.d/autologin.conf ]]; then
    rm -f /etc/sddm.conf.d/autologin.conf
    note "removed   /etc/sddm.conf.d/autologin.conf: GDM logs no one in automatically"
  fi
  # What Omarchy's installer records: the user and session the greeter offers
  # first. install replaces a link in the sddm user's directory, where a
  # redirect would follow it; from a file, as 26.04's install (uutils) fails
  # to read /dev/stdin over a file already there.
  install -d -m 0750 -o sddm -g sddm /var/lib/sddm
  state=$(mktemp)
  printf '[Last]\nSession=omarchy.desktop\nUser=%s\n' "$OMARCHY_USER" >"$state"
  install -m 644 -o sddm -g sddm "$state" /var/lib/sddm/state.conf
  rm -f "$state"
  log "SDDM the display manager, from the next boot"
  make_display_manager sddm /usr/bin/sddm
  note "GDM back: sudo env REPO_DIR=$REPO_DIR $REPO_DIR/install/66-session-root.sh --undo"
  if [[ $(cat "$OMARCHY_HOME/.local/share/keyrings/default" 2>/dev/null) != Default_keyring ]]; then
    note "a password login does not unlock Ubuntu's login keyring under upstream's PAM: $REPO_DIR/bin/omarchy-keyring-passwordless, once, gives Omarchy's passwordless default keyring"
  fi
  # Ubuntu's fingerprint login sits in common-auth, which SDDM's PAM includes;
  # the PAM stays as Ubuntu set it (docs/gotchas.md).
  if grep -qs '^[^#]*pam_fprintd\.so' /etc/pam.d/common-auth; then
    note "a password login waits for a fingerprint first (Ubuntu's fingerprint login, in common-auth): touch the reader, or wait for it to give up; docs/gotchas.md has the way out"
  fi
fi

rm -f "$declined"
install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$REPO_DIR/.applied"
manifest >"$applied"
chown "$OMARCHY_USER:$OMARCHY_USER" "$applied"
