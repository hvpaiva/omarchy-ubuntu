#!/bin/bash
# System-side pieces (root): classic sudo where sudo-rs is the default (--sudo
# does only that; --sudo-due, as the user, says whether it would switch), the
# dev link, the uwsm session env, login-shell env, sudo secure_path, polkit,
# PAM stacks for the shell's lock screen and the polkit dialog, the screen
# recorder's KMS server with the capability it needs.
source "${REPO_DIR:?}/lib/common.sh"
[[ ${1:-} == --sudo-due ]] || need_root

# gpu-screen-recorder runs the gsr-kms-server beside it, or else the first on
# PATH, and asks for root at each recording of a monitor unless that one has
# cap_sys_admin. Upstream's package installs it root's, in /usr/bin, with the
# capability. The build leaves it in ~/.local/bin, the user's, where the next
# build drops the capability: root's copy goes to /usr/local/bin instead, and
# the updater moves each new build's (--gsr-kms-server).
gsr_kms_server() {
  [[ -f $LOCAL_BIN/gsr-kms-server ]] || return 0
  log "gsr-kms-server: root's, in /usr/local/bin, with cap_sys_admin (screen recording without a root prompt)"
  install -m 755 "$LOCAL_BIN/gsr-kms-server" /usr/local/bin/gsr-kms-server
  setcap cap_sys_admin+ep /usr/local/bin/gsr-kms-server
  rm -f "$LOCAL_BIN/gsr-kms-server"
}
if [[ ${1:-} == --gsr-kms-server ]]; then
  gsr_kms_server
  exit 0
fi

# Upstream's package puts default/uwsm/env.d/10-omarchy in /usr/share/uwsm/env.d,
# where uwsm (0.26.1 and later) reads the session's environment; a link through
# the dev link follows the checkout as the package's file follows the package.
# An older uwsm (26.04's 0.25.2) gets the same file from step 50's block in
# ~/.config/uwsm/env. The updater runs only this (--session-env) while the link
# is missing.
session_env() {
  local link=/usr/share/uwsm/env.d/10-omarchy target=/usr/share/omarchy/default/uwsm/env.d/10-omarchy
  [[ $(readlink "$link" 2>/dev/null) == "$target" ]] && return 0
  log "uwsm session env: $link -> $target"
  install -d /usr/share/uwsm/env.d
  ln -sfn "$target" "$link"
}
if [[ ${1:-} == --session-env ]]; then
  session_env
  exit 0
fi

# Upstream's sudoers rules are sudo's (sudo.ws): argument patterns, a
# timestamp on a rule (NOTAFTER), `sudo -N`. 26.04 makes sudo-rs its sudo,
# which has none of them, and keeps classic sudo installed as /usr/bin/sudo.ws
# behind the same alternative; the port selects it, as Ubuntu documents for
# going back (`update-alternatives --auto sudo` returns to sudo-rs). An
# alternative an admin set by hand stays as it is: the rules sudo-rs cannot
# read are then left out (install_sudoers).
# classic_sudo_state: current (sudo.ws is the sudo, or no alternative picks
# one, as on noble), manual (set by hand), missing (no sudo.ws to select) or
# due.
classic_sudo_state() {
  local query
  if ! query=$(update-alternatives --query sudo 2>/dev/null) || grep -qx 'Value: /usr/bin/sudo.ws' <<<"$query"; then
    echo current
  elif grep -qx 'Status: manual' <<<"$query"; then
    echo manual
  elif ! grep -qx 'Alternative: /usr/bin/sudo.ws' <<<"$query"; then
    echo missing
  else
    echo due
  fi
}
classic_sudo() {
  case $(classic_sudo_state) in
    current) ;;
    manual) warn "sudo is $(readlink -f /usr/bin/sudo), set by hand: left as it is; Omarchy's sudoers rules it cannot read stay out" ;;
    missing) warn "no classic sudo (/usr/bin/sudo.ws) to select: Omarchy's sudoers rules $(sudo_name) cannot read stay out" ;;
    due)
      log "sudo: classic sudo (sudo.ws) over sudo-rs, for upstream's sudoers rules"
      update-alternatives --set sudo /usr/bin/sudo.ws >/dev/null
      note "back to sudo-rs: update-alternatives --auto sudo"
      ;;
  esac
}
if [[ ${1:-} == --sudo-due ]]; then
  [[ $(classic_sudo_state) == due ]]
  exit
fi
classic_sudo
if [[ ${1:-} == --sudo ]]; then
  exit 0
fi

bootstrap="$OMARCHY_PATH/default/bash/env-bootstrap"
[[ -r $bootstrap ]] || die "Omarchy checkout not found at $OMARCHY_PATH"

log "dev link: /usr/share/omarchy -> $OMARCHY_PATH"
if [[ ! -L /usr/share/omarchy || $(readlink /usr/share/omarchy) != "$OMARCHY_PATH" ]]; then
  [[ -e /usr/share/omarchy && ! -L /usr/share/omarchy ]] && die "/usr/share/omarchy exists and is not a symlink"
  ln -sfn "$OMARCHY_PATH" /usr/share/omarchy
fi
install_file 644 /etc/omarchy.conf <<EOF
export OMARCHY_PATH="$OMARCHY_PATH"
EOF

session_env

log "login shells (upstream: /etc/profile.d/omarchy.sh); real users only, so root's PATH stays clean"
install_file 644 /etc/profile.d/omarchy.sh <<EOF
[ "\$(id -u)" -ge 1000 ] && [ -r '$bootstrap' ] && . '$bootstrap'
EOF

log "sudo secure_path with the checkout's bin (what omarchy-dev-link writes on Arch)"
printf 'Defaults secure_path="%s/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"\n' "$OMARCHY_PATH" |
  install_sudoers omarchy-dev-path

log "polkit: authenticate as the requesting user"
# Ubuntu offers the whole sudo group as admin identities and the shell's agent
# takes the first one, which on a machine with several admins is someone else.
install_file 644 /etc/polkit-1/rules.d/49-omarchy-self-admin.rules <"$REPO_DIR/etc/polkit-1/rules.d/49-omarchy-self-admin.rules"

log "PAM: lock screen stacks (upstream uses system-local-login and faillock, which Ubuntu lacks)"
install_file 644 /etc/pam.d/omarchy-lock-password <"$REPO_DIR/etc/pam.d/omarchy-lock-password"
has_fingerprint=0
if [[ -x /usr/bin/fprintd-list ]] && /usr/bin/fprintd-list "$OMARCHY_USER" 2>/dev/null | grep -qi finger; then
  has_fingerprint=1
fi
if (( has_fingerprint )); then
  install_file 644 /etc/pam.d/omarchy-lock-fingerprint <"$REPO_DIR/etc/pam.d/omarchy-lock-fingerprint"
  # The polkit dialog only shows its fingerprint mode when /etc/pam.d/polkit-1
  # names pam_fprintd explicitly; Ubuntu has no such file (it falls back to
  # `other` and common-auth). This mirrors what omarchy-setup-security-fingerprint writes.
  install_file 644 /etc/pam.d/polkit-1 <"$REPO_DIR/etc/pam.d/polkit-1"
else
  rm -f /etc/pam.d/omarchy-lock-fingerprint
  if [[ -f /etc/pam.d/polkit-1 ]] && grep -q "omarchy-ubuntu" /etc/pam.d/polkit-1; then
    rm -f /etc/pam.d/polkit-1
  fi
  note "no fingerprint enrolled: fingerprint stacks skipped (enroll with fprintd-enroll and rerun)"
fi

log "brightness: video and i2c groups, keyboard backlight writable by video, i2c-dev for DDC"
# brightnessctl's Ubuntu udev rules hand the display backlight to the video group
# and keyboard LEDs to the input group; the latter also exposes every input
# device, so the LEDs go to video instead. External monitors use ddcutil over
# i2c (upstream adds the user to i2c the same way).
usermod -aG video,i2c "$OMARCHY_USER"
install_file 644 /etc/udev/rules.d/90-omarchy-backlight.rules <"$REPO_DIR/etc/udev/rules.d/90-omarchy-backlight.rules"
install_file 644 /etc/modules-load.d/i2c-dev.conf <<'EOF'
i2c-dev
EOF
modprobe i2c-dev 2>/dev/null || true
udevadm control --reload 2>/dev/null || true
udevadm trigger -s leds -s backlight -c add 2>/dev/null || true
note "group membership applies at the next login"

gsr_kms_server
