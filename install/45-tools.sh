#!/bin/bash
# Everything else Omarchy expects on PATH that Ubuntu 24.04 does not package,
# built from source into ~/.local (or /usr/local for the two libraries below).
#   tensaku (screenshot editor), ttfx (screensaver), cliamp (music TUI),
#   herdr (agent workspace), hyprland-preview-share-picker, gpu-screen-recorder,
#   gtk4-layer-shell, xdg-terminal-exec, hyprpicker.
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
  (cd "$SRC_DIR/$bin" && quietly cargo build --release "$@")
  install -m 0755 "$SRC_DIR/$bin/target/release/$bin" "$LOCAL_BIN/$bin"
}

# gtk4-layer-shell: tensaku and the share picker need >= 1.0; noble has none.
if ! pkg-config --exists 'gtk4-layer-shell-0 >= 1.0'; then
  log "gtk4-layer-shell $GTK4_LAYER_SHELL_VERSION (meson, /usr/local, needs sudo for install)"
  git_checkout "$SRC_DIR/gtk4-layer-shell" https://github.com/wmww/gtk4-layer-shell "$GTK4_LAYER_SHELL_VERSION"
  # Introspection and vapi, on by default, want g-ir-scanner and vapigen;
  # nothing here reaches the library through GObject Introspection (tensaku
  # and the share picker link it from Rust).
  quietly meson setup "$SRC_DIR/gtk4-layer-shell/build" "$SRC_DIR/gtk4-layer-shell" --prefix=/usr/local -Dintrospection=false -Dvapi=false
  ninja -C "$SRC_DIR/gtk4-layer-shell/build"
  quietly sudo ninja -C "$SRC_DIR/gtk4-layer-shell/build" install
  sudo ldconfig
fi

# xdg-terminal-exec: Omarchy launches every terminal through it. It has no
# --version (that would launch a terminal), so the installed one is stamped.
xte_stamp=$REPO_DIR/.applied/xdg-terminal-exec
if [[ ! -x $LOCAL_BIN/xdg-terminal-exec || $(cat "$xte_stamp" 2>/dev/null) != "$XDG_TERMINAL_EXEC_VERSION" ]]; then
  log "xdg-terminal-exec $XDG_TERMINAL_EXEC_VERSION"
  git_checkout "$SRC_DIR/xdg-terminal-exec" https://github.com/Vladimir-csp/xdg-terminal-exec "$XDG_TERMINAL_EXEC_VERSION"
  install -m 0755 "$SRC_DIR/xdg-terminal-exec/xdg-terminal-exec" "$LOCAL_BIN/xdg-terminal-exec"
  mkdir -p "$(dirname "$xte_stamp")" && echo "$XDG_TERMINAL_EXEC_VERSION" >"$xte_stamp"
fi

# hyprpicker: color picker binding and screenshot helpers.
if ! want "$LOCAL_BIN/hyprpicker" "$HYPRPICKER_VERSION"; then
  log "hyprpicker $HYPRPICKER_VERSION"
  git_checkout "$SRC_DIR/hyprpicker" https://github.com/hyprwm/hyprpicker "$HYPRPICKER_VERSION"
  # C++23's <print> arrived with libstdc++ 14; noble's default g++ is 13.
  CXX=g++-14 quietly cmake -S "$SRC_DIR/hyprpicker" -B "$SRC_DIR/hyprpicker/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OMARCHY_HOME/.local"
  quietly cmake --build "$SRC_DIR/hyprpicker/build" -j "$JOBS"
  quietly cmake --install "$SRC_DIR/hyprpicker/build"
fi

# tensaku while upstream's base ships it; omasnap takes over in 4.5, and the
# migration that does so drops this build through omarchy-pkg-ubuntu's recipe.
# Its source lives with its author now (omarchy-pkgs builds the Arch package
# from there); the omacom-io repository is gone, not redirected.
if grep -qx tensaku "$OMARCHY_PATH/install/omarchy-base.packages"; then
  cargo_app tensaku https://github.com/jondkinney/tensaku "$TENSAKU_VERSION" --features ci-release
  install -m 0755 "$SRC_DIR/tensaku/target/release/tensaku-edit" "$LOCAL_BIN/tensaku-edit" 2>/dev/null || true
fi

cargo_app ttfx https://github.com/omacom-io/ttfx "$TTFX_VERSION"

# Installed only: step 57 declares the pinned versions in the port's system-level
# mise config (/etc/mise/conf.d/omarchy-ubuntu.toml), the lowest precedence, so
# a version the user declares in ~/.config/mise/config.toml wins and the port
# never rewrites that file.
# cliamp is one of the preinstalls: once removed it stays out.
mise_tools=("herdr@${HERDR_VERSION#v}")
grep -qx cliamp < <(removed_preinstalls) || mise_tools+=("cliamp@${CLIAMP_VERSION#v}")
for tool in "${mise_tools[@]}"; do
  if ! mise where "$tool" >/dev/null 2>&1; then
    log "${mise_tools[*]} (mise, GitHub releases)"
    mise install -q "${mise_tools[@]}"
    break
  fi
done

cargo_app hyprland-preview-share-picker https://github.com/WhySoBad/hyprland-preview-share-picker "$SHARE_PICKER_VERSION"

# Aether came from a Wails build here until step 15 took its release .deb; the
# ~/.local copy would shadow /usr/bin/aether and double its launcher. The old
# checkout marks that flow; without it, whatever sits at ~/.local/bin/aether is the user's.
if [[ -d $SRC_DIR/aether ]]; then
  log "aether: the earlier Wails build leaves ~/.local (step 15's .deb replaces it)"
  rm -f "$LOCAL_BIN/aether" "$OMARCHY_HOME/.local/share/applications/li.oever.aether.desktop" \
    "$OMARCHY_HOME/.local/share/applications/li.oever.aether.url-handler.desktop" \
    "$OMARCHY_HOME/.local/share/icons/hicolor/512x512/apps/aether.png"
  rm -rf "$SRC_DIR/aether"
fi

# gpu-screen-recorder links the FFmpeg it builds itself (ffmpeg_static: 9.0,
# where upstream's ring carries 9.0.2). noble's 6.1 has no working
# hybrid_fragmented movflags, so its mp4 recordings can stutter. FFmpeg 9 wants
# Vulkan headers newer than noble's: Khronos', at the ring's version, serve
# both builds. A build still linked to noble's FFmpeg is redone.
if ! want "$LOCAL_BIN/gpu-screen-recorder" "$GSR_VERSION" ||
  [[ $(ldd "$LOCAL_BIN/gpu-screen-recorder" 2>/dev/null) == *libavformat* ]]; then
  log "gpu-screen-recorder $GSR_VERSION (meson, FFmpeg built in)"
  git_checkout "$SRC_DIR/vulkan-headers" https://github.com/KhronosGroup/Vulkan-Headers "$VULKAN_HEADERS_VERSION"
  printf '%s\n' "Name: Vulkan-Headers" "Description: Vulkan headers" "Version: ${VULKAN_HEADERS_VERSION#v}" \
    "Cflags: -I$SRC_DIR/vulkan-headers/include" >"$SRC_DIR/vulkan-headers/vulkan.pc"
  git_checkout "$SRC_DIR/gpu-screen-recorder" https://repo.dec05eba.com/gpu-screen-recorder "$GSR_VERSION"
  rm -rf "$SRC_DIR/gpu-screen-recorder/build"
  quietly env PKG_CONFIG_PATH="$SRC_DIR/vulkan-headers:$PKG_CONFIG_PATH" \
    meson setup "$SRC_DIR/gpu-screen-recorder/build" "$SRC_DIR/gpu-screen-recorder" --buildtype=release \
    --prefix="$OMARCHY_HOME/.local" -Dcapabilities=false -Dsystemd=false -Dnvidia_suspend_fix=false \
    -Dffmpeg_static=true -Dc_args="-I$SRC_DIR/vulkan-headers/include"
  quietly ninja -C "$SRC_DIR/gpu-screen-recorder/build"
  quietly meson install -C "$SRC_DIR/gpu-screen-recorder/build"
  note "gsr-kms-server gets cap_sys_admin in install/55-root.sh"
fi

# The companion apps upstream's base lists at this tag, from source, less the
# preinstalls the user removed; the others stay on demand through
# omarchy-pkg-ubuntu's recipes, and the ones already on the machine follow
# their pins.
mapfile -t apps < <(base_apps)
(( ${#apps[@]} == 0 )) || "$REPO_DIR/bin/omarchy-build-app" "${apps[@]}"
"$REPO_DIR/bin/omarchy-build-app" --installed
