#!/bin/bash
# Everything else Omarchy expects on PATH that Ubuntu 24.04 does not package,
# built from source into ~/.local (or /usr/local for the two libraries below).
#   tensaku (screenshot editor), ttfx (screensaver), cliamp (music TUI),
#   herdr (agent workspace), aether (theming app), hyprland-preview-share-picker,
#   gpu-screen-recorder, gtk4-layer-shell, xdg-terminal-exec, hyprpicker.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export PATH="$OMARCHY_HOME/.cargo/bin:$OMARCHY_HOME/.local/share/mise/shims:$LOCAL_BIN:$PATH"
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}
mkdir -p "$SRC_DIR" "$LOCAL_BIN"

installed_version() { "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
want() { [[ $(installed_version "$1") == "${2#v}" ]]; }

cargo_app() { # cargo_app <bin> <repo url> <tag> [extra cargo args...]
  local bin=$1 url=$2 tag=$3
  shift 3
  if want "$LOCAL_BIN/$bin" "$tag"; then note "unchanged $bin ${tag#v}"; return; fi
  log "$bin $tag"
  git_checkout "$SRC_DIR/$bin" "$url" "$tag"
  git -C "$SRC_DIR/$bin" submodule update --init --depth 1 --quiet 2>/dev/null || true
  (cd "$SRC_DIR/$bin" && cargo build --release "$@" 2>&1 | tail -2)
  install -m 0755 "$SRC_DIR/$bin/target/release/$bin" "$LOCAL_BIN/$bin"
}

# gtk4-layer-shell: tensaku and the share picker need >= 1.0; noble has none.
if ! pkg-config --exists 'gtk4-layer-shell-0 >= 1.0'; then
  log "gtk4-layer-shell $GTK4_LAYER_SHELL_VERSION (meson, /usr/local, needs sudo for install)"
  git_checkout "$SRC_DIR/gtk4-layer-shell" https://github.com/wmww/gtk4-layer-shell "$GTK4_LAYER_SHELL_VERSION"
  meson setup "$SRC_DIR/gtk4-layer-shell/build" "$SRC_DIR/gtk4-layer-shell" --prefix=/usr/local >/dev/null
  ninja -C "$SRC_DIR/gtk4-layer-shell/build"
  sudo ${SUDO_ASKPASS:+-A} ninja -C "$SRC_DIR/gtk4-layer-shell/build" install >/dev/null
  sudo ${SUDO_ASKPASS:+-A} ldconfig
fi

# xdg-terminal-exec: Omarchy launches every terminal through it.
if ! have xdg-terminal-exec; then
  log "xdg-terminal-exec $XDG_TERMINAL_EXEC_VERSION"
  git_checkout "$SRC_DIR/xdg-terminal-exec" https://github.com/Vladimir-csp/xdg-terminal-exec "$XDG_TERMINAL_EXEC_VERSION"
  install -m 0755 "$SRC_DIR/xdg-terminal-exec/xdg-terminal-exec" "$LOCAL_BIN/xdg-terminal-exec"
fi

# hyprpicker: color picker binding and screenshot helpers.
if ! have hyprpicker; then
  log "hyprpicker $HYPRPICKER_VERSION"
  git_checkout "$SRC_DIR/hyprpicker" https://github.com/hyprwm/hyprpicker "$HYPRPICKER_VERSION"
  cmake -S "$SRC_DIR/hyprpicker" -B "$SRC_DIR/hyprpicker/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OMARCHY_HOME/.local" >/dev/null
  cmake --build "$SRC_DIR/hyprpicker/build" -j "$JOBS" >/dev/null
  cmake --install "$SRC_DIR/hyprpicker/build" >/dev/null
fi

cargo_app tensaku https://github.com/omacom-io/tensaku "$TENSAKU_VERSION" --features ci-release
install -m 0755 "$SRC_DIR/tensaku/target/release/tensaku-edit" "$LOCAL_BIN/tensaku-edit" 2>/dev/null || true

cargo_app ttfx https://github.com/omacom-io/ttfx "$TTFX_VERSION"

log "herdr $HERDR_VERSION and cliamp $CLIAMP_VERSION (mise, GitHub releases)"
mise use --global "herdr@${HERDR_VERSION#v}" "cliamp@${CLIAMP_VERSION#v}"

cargo_app hyprland-preview-share-picker https://github.com/WhySoBad/hyprland-preview-share-picker "$SHARE_PICKER_VERSION"

if [[ ! -x $LOCAL_BIN/aether ]] || ! git -C "$SRC_DIR/aether" describe --tags 2>/dev/null | grep -q "$AETHER_VERSION"; then
  log "aether $AETHER_VERSION (Wails, webkit2gtk 4.1)"
  git_checkout "$SRC_DIR/aether" https://github.com/omacom/aether "$AETHER_VERSION"
  (cd "$SRC_DIR/aether" && PATH="$(go env GOPATH)/bin:$PATH" wails build -tags webkit2_41 2>&1 | tail -1)
  install -m 0755 "$SRC_DIR/aether/build/bin/aether" "$LOCAL_BIN/aether"
  install -Dm644 "$SRC_DIR/aether/li.oever.aether.desktop" "$OMARCHY_HOME/.local/share/applications/li.oever.aether.desktop"
  install -Dm644 "$SRC_DIR/aether/li.oever.aether.url-handler.desktop" "$OMARCHY_HOME/.local/share/applications/li.oever.aether.url-handler.desktop"
  install -Dm644 "$SRC_DIR/aether/assets/aether-icon-512.png" "$OMARCHY_HOME/.local/share/icons/hicolor/512x512/apps/aether.png"
  xdg-mime default li.oever.aether.url-handler.desktop x-scheme-handler/aether 2>/dev/null || true
fi

if ! want "$LOCAL_BIN/gpu-screen-recorder" "$GSR_VERSION"; then
  log "gpu-screen-recorder $GSR_VERSION (meson)"
  git_checkout "$SRC_DIR/gpu-screen-recorder" https://repo.dec05eba.com/gpu-screen-recorder "$GSR_VERSION"
  rm -rf "$SRC_DIR/gpu-screen-recorder/build"
  meson setup "$SRC_DIR/gpu-screen-recorder/build" "$SRC_DIR/gpu-screen-recorder" --buildtype=release \
    --prefix="$OMARCHY_HOME/.local" -Dcapabilities=false -Dsystemd=false -Dnvidia_suspend_fix=false >/dev/null
  ninja -C "$SRC_DIR/gpu-screen-recorder/build" >/dev/null
  meson install -C "$SRC_DIR/gpu-screen-recorder/build" >/dev/null
  note "gsr-kms-server gets cap_sys_admin in install/55-root.sh"
fi

"$REPO_DIR/bin/omarchy-build-qt-apps"
