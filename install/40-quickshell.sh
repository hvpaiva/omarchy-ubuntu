#!/bin/bash
# Quickshell (the runtime of omarchy-shell), the build Omarchy packages: its
# commit and its patch, built against the aqt Qt and installed under ~/.local.
# Ubuntu has no Quickshell package for 24.04; the port builds Omarchy's on
# every release.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export PATH="$QT_DIR/bin:$PATH"
[[ -x $QT_DIR/bin/qmake6 ]] || die "Qt not found in $QT_DIR (run install/20-qt.sh)"

src=$SRC_DIR/quickshell

# --version carries the revision and, through DISTRIBUTOR below, the Ubuntu
# release and the Qt it was built against; a new Qt or a release upgrade is a
# rebuild as much as a new revision.
installed=$("$LOCAL_BIN/quickshell" --version 2>/dev/null || true)
if grep -q "${QUICKSHELL_VERSION#v}" <<<"$installed" && grep -q "Ubuntu $UBUNTU_VERSION, Qt $QT_VERSION via" <<<"$installed"; then
  note "unchanged quickshell ${QUICKSHELL_VERSION#v} on Qt $QT_VERSION"
  exit 0
fi

log "quickshell $QUICKSHELL_VERSION source"
mkdir -p "$SRC_DIR"
# A previous run left Omarchy's patch applied, and git refuses to switch commits
# over a modified file: pristine tree first (its build directory goes with it).
if [[ -d $src/.git ]]; then
  git -C "$src" checkout --quiet -- . && git -C "$src" clean --quiet -fdx
fi
git_checkout "$src" https://github.com/quickshell-mirror/quickshell "$QUICKSHELL_VERSION"

# Omarchy's package carries a patch for Qt 6.12, where QtQuick gained a `Color`
# type that shadows the shell's palette singleton: with it the shell's
# `//@ pragma OmarchyLoadPatch` makes Quickshell import QtQuick 6.11 in every
# QML file. The same patch, from the same commit of omarchy-pkgs.
patch=$SRC_DIR/quickshell-omarchy-$OMARCHY_PKGS_COMMIT.patch
if [[ ! -s $patch ]]; then
  log "Omarchy's Quickshell patch (omarchy-pkgs $OMARCHY_PKGS_COMMIT)"
  curl -fsSL -o "$patch" "https://raw.githubusercontent.com/omacom/omarchy-pkgs/$OMARCHY_PKGS_COMMIT/pkgbuilds/quickshell/load_qtquick_611.patch"
fi
git -C "$src" apply "$patch"

cxxflags=$(wayland_compat_cflags)

log "configure + build"
quietly cmake -S "$src" -B "$src/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_CXX_FLAGS="$cxxflags" \
  -DCMAKE_PREFIX_PATH="$QT_DIR" \
  -DCMAKE_INSTALL_PREFIX="$OMARCHY_HOME/.local" \
  -DCMAKE_INSTALL_RPATH="$QT_DIR/lib" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
  -DDISTRIBUTOR="omarchy-ubuntu (Ubuntu $UBUNTU_VERSION, Qt $QT_VERSION via aqtinstall)" \
  -DCRASH_HANDLER=OFF -DX11=OFF -DI3=OFF -DSERVICE_GREETD=OFF
ninja -C "$src/build" -j "$JOBS"
quietly ninja -C "$src/build" install
ln -sfn "$LOCAL_BIN/quickshell" "$LOCAL_BIN/qs"
"$LOCAL_BIN/quickshell" --version
