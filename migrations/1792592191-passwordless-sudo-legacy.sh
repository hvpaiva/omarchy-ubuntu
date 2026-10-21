#!/bin/bash
# Upstream's 1788163635 takes away the passwordless-sudo grants the old helper
# wrote through the 4.5 helper's __migrate, whose root lock refuses Ubuntu's
# world-writable /run/lock. The root half beside this file does that part and
# writes the marker the helper's __migration-complete checks, so upstream's
# migration then passes here without asking for sudo, as on Arch.
#
# Pending (75) until the checkout carries that migration: before 4.5 the old
# helper is the live one, and its grants are its own to manage.
[[ -f ${OMARCHY_PATH:?}/migrations/1788163635.sh ]] || exit 75
run_root env OMARCHY_USER="$(id -un)" REPO_DIR="${PORT_DIR:?}" "${BASH_SOURCE[0]%.sh}-root.sh"
