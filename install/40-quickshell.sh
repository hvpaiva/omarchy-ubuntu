#!/bin/bash
# Quickshell (the runtime of omarchy-shell), built against the aqt Qt and
# installed under ~/.local. Ubuntu has no Quickshell package for 24.04.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export PATH="$QT_DIR/bin:$PATH"
[[ -x $QT_DIR/bin/qmake6 ]] || die "Qt not found in $QT_DIR (run install/20-qt.sh)"

src=$SRC_DIR/quickshell
compat=$SRC_DIR/quickshell-compat/include

if "$LOCAL_BIN/quickshell" --version 2>/dev/null | grep -q "${QUICKSHELL_VERSION#v}"; then
  note "unchanged quickshell ${QUICKSHELL_VERSION#v}"
  exit 0
fi

log "quickshell $QUICKSHELL_VERSION source"
mkdir -p "$SRC_DIR"
git_checkout "$src" https://github.com/quickshell-mirror/quickshell "$QUICKSHELL_VERSION"

# Qt >= 6.10's private qwayland-wayland.h declares wl_fixes, which only exists in
# libwayland >= 1.23's generated header; noble ships 1.22. The two headers share
# the WAYLAND_CLIENT_PROTOCOL_H guard, so a newer generated header shadows the
# system one at compile time only. Nothing in the Qt libraries needs wl_fixes at
# runtime, so the resulting binary runs fine against libwayland 1.22.
if [[ ! -f $compat/wayland-client-protocol.h ]]; then
  log "compat header from wayland $WAYLAND_XML_VERSION protocol XML"
  mkdir -p "$compat"
  curl -fsSL -o "$SRC_DIR/quickshell-compat/wayland-$WAYLAND_XML_VERSION.xml" \
    "https://gitlab.freedesktop.org/wayland/wayland/-/raw/$WAYLAND_XML_VERSION/protocol/wayland.xml"
  wayland-scanner client-header "$SRC_DIR/quickshell-compat/wayland-$WAYLAND_XML_VERSION.xml" "$compat/wayland-client-protocol.h"
  cp /usr/include/wayland-client.h "$compat/wayland-client.h"
fi

log "configure + build"
cmake -S "$src" -B "$src/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_CXX_FLAGS="-I$compat" \
  -DCMAKE_PREFIX_PATH="$QT_DIR" \
  -DCMAKE_INSTALL_PREFIX="$OMARCHY_HOME/.local" \
  -DCMAKE_INSTALL_RPATH="$QT_DIR/lib" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
  -DDISTRIBUTOR="omarchy-ubuntu (Ubuntu 24.04, Qt $QT_VERSION via aqtinstall)" \
  -DCRASH_HANDLER=OFF -DX11=OFF -DI3=OFF -DSERVICE_GREETD=OFF >/dev/null
ninja -C "$src/build" -j "$JOBS"
ninja -C "$src/build" install >/dev/null
ln -sfn "$LOCAL_BIN/quickshell" "$LOCAL_BIN/qs"
"$LOCAL_BIN/quickshell" --version
