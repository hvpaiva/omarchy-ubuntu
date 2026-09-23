#!/bin/bash
# Expose the port's commands and record the layout.
source "${REPO_DIR:?}/lib/common.sh"
need_user

mkdir -p "$LOCAL_BIN"
ln -sfn "$REPO_DIR/bin/omarchy-update-ubuntu" "$LOCAL_BIN/omarchy-update-ubuntu"
ln -sfn "$REPO_DIR/bin/omarchy-build-qt-apps" "$LOCAL_BIN/omarchy-build-qt-apps"
ln -sfn "$REPO_DIR/bin/omarchy-share-picker-region" "$LOCAL_BIN/omarchy-share-picker-region"
ln -sfn "$REPO_DIR/bin/omarchy-audio-input-denoise" "$LOCAL_BIN/omarchy-audio-input-denoise"
note "omarchy-update-ubuntu and omarchy-build-qt-apps on PATH (~/.local/bin)"

cat <<EOF

Installed layout:
  Omarchy checkout      $OMARCHY_PATH  (branch $OMARCHY_BRANCH on $OMARCHY_TAG; /usr/share/omarchy -> it)
  Qt                    $QT_DIR
  Sources               $SRC_DIR
  Binaries              $LOCAL_BIN
  Hyprland config       $OMARCHY_HOME/.config/hypr/*.lua
  Session entry         /usr/share/wayland-sessions/omarchy.desktop (uwsm), 'Hyprland' as fallback
  Update                omarchy-update-ubuntu (also behind the menu's Update > Omarchy)
EOF
