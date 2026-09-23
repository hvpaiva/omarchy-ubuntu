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
log "policy directories"
setup_dir /etc/chromium/policies/managed
if have google-chrome || have google-chrome-stable; then
  setup_dir /etc/opt/chrome/policies/managed
fi

# Remember what was applied so the updater can tell when upstream changes it.
applied=$REPO_DIR/.applied
install -d -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$applied"
install -m 0644 -o "$OMARCHY_USER" -g "$OMARCHY_USER" "$OMARCHY_PATH/etc/sudoers.d/omarchy-theme-browser" "$applied/omarchy-theme-browser"
