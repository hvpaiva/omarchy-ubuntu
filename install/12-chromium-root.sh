#!/bin/bash
# Chromium, Omarchy's default browser (root). Ubuntu only ships Chromium as a
# snap, and the snap breaks every place Omarchy touches the browser: its desktop
# file is not chromium.desktop (first-run's xdg-settings call and the web app
# launcher look for that name under /usr/share/applications), confinement hides
# the extensions Omarchy loads from ~/.local/share/omarchy, and it ignores
# /etc/chromium/policies and ~/.config/chromium-flags.conf. The xtradeb PPA
# builds Debian's chromium package for noble, which matches Arch's layout.
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "apt pin: only chromium* from the xtradeb PPA"
install_file 644 /etc/apt/preferences.d/omarchy-xtradeb-chromium <"$REPO_DIR/etc/apt/preferences.d/omarchy-xtradeb-chromium"

if ! grep -rqs 'xtradeb/apps' /etc/apt/sources.list.d/; then
  log "xtradeb PPA"
  # -n: add-apt-repository's own update shrugs off an index it could not
  # fetch, and chromium then has no candidate; the apt_retry update does not.
  add-apt-repository -y -n ppa:xtradeb/apps
fi
apt_retry update -qq

# The pin must hold: an upgrade may take nothing from the PPA, and installing
# Chromium may take nothing but chromium* from it. One awk reads each plan
# whole: a grep -q that quits at the first stray line can kill the commands
# before it with SIGPIPE, which pipefail turns into no match.
stray() { awk '/^Inst / && /xtradeb/ && !/^Inst chromium(-[a-z0-9-]+)? /'; }
plan=$(LC_ALL=C apt-get -s dist-upgrade | stray)
if [[ -n $plan ]]; then
  echo "$plan" >&2
  die "the pin is not holding: an upgrade would pull the packages above from the xtradeb PPA"
fi
plan=$(LC_ALL=C apt-get -s install --no-install-recommends chromium chromium-sandbox | stray)
if [[ -n $plan ]]; then
  echo "$plan" >&2
  die "installing chromium would pull other packages from the xtradeb PPA"
fi

# Debian's first-run preferences turn Safe Browsing and sign-in off, switch the
# search engine to DuckDuckGo and set debian.org as the home page. Arch ships
# none; Omarchy writes its own (install/config/theme-system.sh), which only
# skips the EULA and lets the theme policy pick the colour scheme. Move
# Debian's file aside (the package keeps updating the diverted copy) and put
# Omarchy's where Debian's build and upstream's both look.
if ! dpkg-divert --list /etc/chromium/master_preferences | grep -q .; then
  log "divert Debian's Chromium first-run preferences"
  dpkg-divert --add --rename --divert /etc/chromium/master_preferences.debian /etc/chromium/master_preferences
fi
omarchy_prefs='{"distribution":{"require_eula":false},"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'
install_file 644 /etc/chromium/master_preferences <<<"$omarchy_prefs"
install_file 644 /usr/lib/chromium/initial_preferences <<<"$omarchy_prefs"

# chromium-sandbox (the setuid helper) is a Recommends of chromium; the
# AppArmor profile below lets the namespace sandbox work, the helper is the
# fallback.
if ! apt_installed chromium || ! apt_installed chromium-sandbox; then
  log "chromium"
  apt_retry install -y --no-install-recommends chromium chromium-sandbox
fi

log "Chromium reads ~/.config/chromium-flags.conf like on Arch"
install_file 644 /etc/chromium.d/omarchy-user-flags <"$REPO_DIR/etc/chromium.d/omarchy-user-flags"

log "AppArmor profile so Chromium may use user namespaces"
install_file 644 /etc/apparmor.d/omarchy-chromium <"$REPO_DIR/etc/apparmor.d/omarchy-chromium"
# Loaded now where AppArmor runs: the parser alone is not enough, it needs the
# kernel's side (securityfs), which a container or a kernel built without
# AppArmor lacks. The profile then waits in /etc/apparmor.d for AppArmor, if ever.
if have apparmor_parser && [[ -d /sys/kernel/security/apparmor ]]; then
  apparmor_parser -r /etc/apparmor.d/omarchy-chromium
else
  note "AppArmor not running: the profile is in place, not loaded"
fi

note "chromium $(dpkg-query -W -f='${Version}' chromium)"
