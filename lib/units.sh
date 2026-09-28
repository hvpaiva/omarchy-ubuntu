#!/bin/bash
# Omarchy's user units on Ubuntu. Source, do not execute.
#
# Every unit upstream ships in default/systemd/user is installed (ExecStart
# rewritten to the dev link) except the ones below, so a unit added upstream
# arrives with the next update instead of waiting for someone to notice it.
# Which units get *enabled* is upstream's own list (install/user/first-run/
# enable-user-units.sh), mirrored in install/65-session.sh.

OMARCHY_UNITS_SKIP=(
  omarchy-speaker-tuning.service # needs the tuning upstream's install/hardware/speaker-tuning.sh writes for supported laptops; the port has no such step
)

# omarchy_units <default/systemd/user dir>: the unit file names to install.
omarchy_units() {
  local f name skip
  for f in "$1"/*.service; do
    [[ -f $f ]] || continue
    name=$(basename "$f")
    for skip in "${OMARCHY_UNITS_SKIP[@]}"; do
      [[ $name == "$skip" ]] && continue 2
    done
    printf '%s\n' "$name"
  done
}
