#!/bin/bash
# Upstream's 1788862626 (the Elgato Cam Link 4K as a 16:9 virtual camera) on
# Ubuntu. noble's v4l2loopback 0.12.7 cannot add a device at runtime, and its
# v4l2-relayd 0.1.2 has neither the per-camera template upstream's units extend
# nor a base service that stays idle. The root half beside this file supplies
# what noble lacks; upstream's migration then runs as it is, here rather than
# in the updater's loop, where lib/migrations.sh marks it done so it never runs
# before this.
#
# Pending (75) until the checkout carries that migration, or while v4l2loopback
# is held and cannot take the new device (the next boot loads it with it).
[[ -f ${OMARCHY_PATH:?}/migrations/1788862626.sh ]] || exit 75
omarchy-hw-elgato-camlink-4k || exit 0
run_root env OMARCHY_USER="$(id -un)" REPO_DIR="${PORT_DIR:?}" "${BASH_SOURCE[0]%.sh}-root.sh" || exit
bash -euo pipefail "$OMARCHY_PATH/migrations/1788862626.sh"
