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

if ! have go; then
  log "Go via mise"
  mise use --global go@latest
fi

if ! have wails && [[ ! -x $(go env GOPATH)/bin/wails ]]; then
  log "Wails CLI (aether)"
  go install github.com/wailsapp/wails/v2/cmd/wails@v2.16.0
fi

note "cargo $(cargo --version | cut -d' ' -f2), $(go version | cut -d' ' -f3)"
