#!/bin/bash
# Toolchains for the source builds: Rust (rustup) and mise, which also carries
# herdr and cliamp for step 45. Nothing here is system-wide.
source "${REPO_DIR:?}/lib/common.sh"
need_user

if ! have cargo; then
  log "Rust via rustup"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
fi
export PATH="$OMARCHY_HOME/.cargo/bin:$PATH"

# mise at the version Arch's snapshot carries (versions.env), through its own
# installer and self-update; upstream's lazy shims need a current one. The
# port's copy is ~/.local/bin/mise, ahead of a packaged /usr/bin/mise, which
# is root's and cannot self-update as the user.
export PATH="$LOCAL_BIN:$OMARCHY_HOME/.local/share/mise/shims:$PATH"
if [[ ! -x $LOCAL_BIN/mise ]]; then
  log "mise $MISE_VERSION (https://mise.run)"
  curl -fsSL https://mise.run | MISE_VERSION="v$MISE_VERSION" sh
fi
if [[ $(mise --version 2>/dev/null | cut -d' ' -f1) != "$MISE_VERSION" ]]; then
  log "mise $MISE_VERSION (self-update)"
  # The bare version: self-update adds the tag's "v" itself, where the
  # installer above wants it given.
  mise self-update -y "$MISE_VERSION" >/dev/null
fi

note "cargo $(cargo --version | cut -d' ' -f2), mise $(mise --version | cut -d' ' -f1)"
