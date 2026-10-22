#!/bin/bash
# Expose the port's commands and record the layout.
# shellcheck source=../lib/common.sh
source "${REPO_DIR:?}/lib/common.sh"
need_user

mkdir -p "$LOCAL_BIN"
for cmd in omarchy-update-ubuntu omarchy-channel-ubuntu omarchy-upstream-check omarchy-build-app omarchy-build-qt-apps \
  omarchy-share-picker-region omarchy-audio-input-denoise; do
  ln -sfn "$REPO_DIR/bin/$cmd" "$LOCAL_BIN/$cmd"
done
note "omarchy-update-ubuntu, omarchy-channel-ubuntu, omarchy-upstream-check, omarchy-build-app and omarchy-build-qt-apps on PATH (~/.local/bin)"

cat <<EOF

Installed layout:
  Omarchy checkout      $OMARCHY_PATH  (branch $OMARCHY_BRANCH, $OMARCHY_CHANNEL channel on $(git -C "$OMARCHY_PATH" describe --tags --always); /usr/share/omarchy -> it)
  Qt                    $QT_DIR
  Sources               $SRC_DIR
  Binaries              $LOCAL_BIN
  Hyprland config       $OMARCHY_HOME/.config/hypr/*.lua
  Session entry         /usr/share/wayland-sessions/omarchy.desktop (uwsm), 'Hyprland' as fallback
  Update                omarchy-update-ubuntu (also behind the menu's Update > Omarchy)
EOF
