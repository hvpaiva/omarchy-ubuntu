#!/bin/bash
# Qt for Quickshell and the Qt Quick apps. Ubuntu 24.04 ships Qt 6.4; Quickshell
# 0.3 needs >= 6.6 and Omarchy's shell is written against 6.11. aqtinstall fetches
# the official Qt binaries into ~/.local/opt/Qt without touching system packages.
source "${REPO_DIR:?}/lib/common.sh"
need_user

if ! have aqt; then
  log "aqtinstall via pipx"
  pipx install aqtinstall >/dev/null
  pipx ensurepath >/dev/null 2>&1 || true
  export PATH="$LOCAL_BIN:$PATH"
fi

if [[ -x $QT_DIR/bin/qmake6 && -f $QT_DIR/lib/libQt6Multimedia.so ]]; then
  note "unchanged Qt $QT_VERSION in $QT_DIR"
  exit 0
fi

log "Qt $QT_VERSION ($QT_ARCHIVES)"
# shellcheck disable=SC2086
aqt install-qt linux desktop "$QT_VERSION" linux_gcc_64 -m $QT_MODULES --archives $QT_ARCHIVES -O "$OMARCHY_HOME/.local/opt/Qt"
"$QT_DIR/bin/qmake6" -query QT_VERSION
