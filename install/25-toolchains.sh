#!/bin/bash
# Language toolchains for the source builds: Rust (rustup), Go (mise),
# the Wails CLI for aether. Nothing here is system-wide.
source "${REPO_DIR:?}/lib/common.sh"
need_user

if ! have cargo; then
  log "Rust via rustup"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
fi
export PATH="$OMARCHY_HOME/.cargo/bin:$PATH"

if ! have mise; then
  log "mise (https://mise.jdx.dev)"
  curl -fsSL https://mise.run | sh
fi
export PATH="$LOCAL_BIN:$OMARCHY_HOME/.local/share/mise/shims:$PATH"

# Installed, not `mise use`d: ~/.config/mise/config.toml is the user's (their
# dotfiles carry it between machines). Step 57 declares go in the port's
# system-level mise config, which the user's own declaration overrides.
if ! have go; then
  log "Go via mise"
  mise install -q go@latest
  PATH="$(mise where go@latest)/bin:$PATH"
fi

if ! have wails && [[ ! -x $(go env GOPATH)/bin/wails ]]; then
  log "Wails CLI (aether)"
  go install github.com/wailsapp/wails/v2/cmd/wails@v2.16.0
fi

note "cargo $(cargo --version | cut -d' ' -f2), $(go version | cut -d' ' -f3)"
