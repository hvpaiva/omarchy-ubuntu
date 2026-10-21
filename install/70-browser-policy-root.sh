#!/bin/bash
# Browser theme policy (root). Upstream's omarchy-theme-set-browser-policy always
# re-execs the packaged copy at /usr/bin and its sudoers rule grants %wheel; here
# the checkout lives in $HOME and the admin group is sudo. Firefox on Ubuntu is a
# snap and does not read /usr/lib/firefox/distribution, so only Chromium-family
# policy directories are prepared (Chromium always, Chrome when installed).
source "${REPO_DIR:?}/lib/common.sh"
need_root

log "packaged copy of the policy helper"
install -m 0755 -o root -g root -T "$OMARCHY_PATH/bin/omarchy-theme-set-browser-policy" /usr/bin/omarchy-theme-set-browser-policy

log "sudoers rule (%wheel -> %sudo)"
staged=$(mktemp)
sed 's/^%wheel /%sudo /' "$OMARCHY_PATH/etc/sudoers.d/omarchy-theme-browser" >"$staged"
visudo -cf "$staged" >/dev/null
install_file 440 /etc/sudoers.d/omarchy-theme-browser <"$staged"
rm -f "$staged"

# omarchy-language (4.5) elevates through /usr/bin/omarchy-locale-generate the
# same way; its rule names every language code, so the copy and the rule move
# together.
if [[ -f $OMARCHY_PATH/etc/sudoers.d/omarchy-locale-generate ]]; then
  log "packaged copy of the locale helper and its sudoers rule (%wheel -> %sudo)"
  install -m 0755 -o root -g root -T "$OMARCHY_PATH/bin/omarchy-locale-generate" /usr/bin/omarchy-locale-generate
  staged=$(mktemp)
  sed 's/^%wheel /%sudo /' "$OMARCHY_PATH/etc/sudoers.d/omarchy-locale-generate" >"$staged"
  visudo -cf "$staged" >/dev/null
  install_file 440 /etc/sudoers.d/omarchy-locale-generate <"$staged"
  rm -f "$staged"
elif [[ -e /usr/bin/omarchy-locale-generate || -e /etc/sudoers.d/omarchy-locale-generate ]]; then
  log "locale helper and its sudoers rule: not at this tag; removed"
  rm -f /usr/bin/omarchy-locale-generate /etc/sudoers.d/omarchy-locale-generate
fi

setup_dir() {
  local d=$1 p=""
  local IFS=/
  for part in $d; do
    [[ -n $part ]] || continue
    p="$p/$part"
    if [[ -L $p || ( -e $p && ! -d $p ) ]]; then rm -rf -- "$p"; fi
    install -d -m 0755 -o root -g root "$p"
  done
  find "$d" -mindepth 1 -maxdepth 1 ! -user root -exec rm -rf -- {} +
}
# Links reach the browser through omarchy-browser.desktop since 4.0.5, so the
# browser must not offer to make itself the default and rewrite mimeapps.list
# behind Omarchy's back (upstream's browser_policy_install_defaults).
defaults=$OMARCHY_PATH/default/chromium/policies/omarchy.json
install_defaults() {
  [[ -f $defaults ]] || { note "not yet upstream: default/chromium/policies/omarchy.json"; return 0; }
  install -m 0644 -o root -g root -T "$defaults" "$1/omarchy.json"
}
log "policy directories"
setup_dir /etc/chromium/policies/managed
install_defaults /etc/chromium/policies/managed
if have google-chrome || have google-chrome-stable; then
  setup_dir /etc/opt/chrome/policies/managed
  install_defaults /etc/opt/chrome/policies/managed
fi

# Remember what was applied so the updater can tell when upstream changes it.
applied=$REPO_DIR/.applied
install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$applied"
install -m 0644 -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$OMARCHY_PATH/etc/sudoers.d/omarchy-theme-browser" "$applied/omarchy-theme-browser"
if [[ -f $OMARCHY_PATH/etc/sudoers.d/omarchy-locale-generate ]]; then
  install -m 0644 -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$OMARCHY_PATH/etc/sudoers.d/omarchy-locale-generate" "$applied/omarchy-locale-generate"
else
  rm -f "$applied/omarchy-locale-generate"
fi
