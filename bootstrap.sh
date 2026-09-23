#!/bin/bash
# Omarchy 4 on Ubuntu 24.04: one entry point, idempotent, resumable.
#
#   git clone <this repo> ~/.local/share/omarchy-ubuntu
#   ~/.local/share/omarchy-ubuntu/bootstrap.sh            # everything
#   ~/.local/share/omarchy-ubuntu/bootstrap.sh 40 45      # only some steps
#   ~/.local/share/omarchy-ubuntu/bootstrap.sh --list
#
# Root steps (name ends in -root.sh) run through pkexec when a graphical
# session with a polkit agent is up, otherwise through sudo. Everything else
# runs as you. Re-running is safe: each step checks what is already in place.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export REPO_DIR
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

need_user

if ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
  warn "this bootstrap is written for Ubuntu 24.04; continuing anyway"
fi

steps=("$REPO_DIR"/install/[0-9][0-9]-*.sh)

if [[ ${1:-} == "--list" ]]; then
  for s in "${steps[@]}"; do basename "$s"; done
  exit 0
fi

selected=("$@")
run_step() {
  local step=$1 name
  name=$(basename "$step")
  if (( ${#selected[@]} > 0 )); then
    local match=0
    for want in "${selected[@]}"; do [[ $name == "$want"* ]] && match=1; done
    (( match )) || return 0
  fi
  log "$name"
  if [[ $name == *-root.sh ]]; then
    run_root "$step"
  else
    "$step"
  fi
}

for step in "${steps[@]}"; do
  run_step "$step"
done

log "done"
note "Log out and pick 'Omarchy (Hyprland uwsm)' in GDM (the gear icon), or reboot: autologin points at it."
note "Afterwards: omarchy-theme-set <theme>, Super+Space for the menu, Super+K for keybindings."
