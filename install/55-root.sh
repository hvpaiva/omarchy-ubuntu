#!/bin/bash
# System-side pieces (root): the dev link, login-shell env, sudo secure_path,
# polkit, PAM stacks for the shell's lock screen and the polkit dialog, the
# capability the screen recorder's KMS server needs.
source "${REPO_DIR:?}/lib/common.sh"
need_root

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

log "login shells (upstream: /etc/profile.d/omarchy.sh); real users only, so root's PATH stays clean"
install_file 644 /etc/profile.d/omarchy.sh <<EOF
[ "\$(id -u)" -ge 1000 ] && [ -r '$bootstrap' ] && . '$bootstrap'
EOF

log "sudo secure_path with the checkout's bin (what omarchy-dev-link writes on Arch)"
staged=$(mktemp)
printf 'Defaults secure_path="%s/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"\n' "$OMARCHY_PATH" >"$staged"
visudo -cf "$staged" >/dev/null
install_file 440 /etc/sudoers.d/omarchy-dev-path <"$staged"
rm -f "$staged"

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

if [[ -x $LOCAL_BIN/gsr-kms-server ]]; then
  log "cap_sys_admin on gsr-kms-server (screen recording without a root prompt)"
  setcap cap_sys_admin+ep "$LOCAL_BIN/gsr-kms-server"
fi
