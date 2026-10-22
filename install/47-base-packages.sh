#!/bin/bash
# Upstream's default package set, what Omarchy's installer lays down on a new
# machine (omarchy-pkg-defaults from 4.5, install/omarchy-base.packages
# before), through omarchy-pkg-ubuntu: what Ubuntu or the steps before put
# here already is left as it is, a skip recipe stands for what does not apply
# on Ubuntu, the rest comes through its alias or recipe. Like the installer it
# runs at bootstrap and never from the updater, and the preinstalls the user
# removed stay removed.
source "${REPO_DIR:?}/lib/common.sh"
need_user

export OMARCHY_PATH
export PATH="$OMARCHY_PATH/bin:$OMARCHY_HOME/.cargo/bin:$OMARCHY_HOME/.local/share/mise/shims:$LOCAL_BIN:$PATH"
resolver=$OMARCHY_PATH/bin/omarchy-pkg-ubuntu
[[ -x $resolver ]] || die "no omarchy-pkg-ubuntu in $OMARCHY_PATH: step 30 first"

if [[ -x $OMARCHY_PATH/bin/omarchy-pkg-defaults ]]; then
  mapfile -t names < <("$OMARCHY_PATH/bin/omarchy-pkg-defaults" x86)
else
  mapfile -t names < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$OMARCHY_PATH/install/omarchy-base.packages")
fi
(( ${#names[@]} > 0 )) || die "no default package set in $OMARCHY_PATH"

removed=$(removed_preinstalls)
if [[ -n $removed ]]; then
  mapfile -t names < <(printf '%s\n' "${names[@]}" | grep -vxF -f <(printf '%s\n' "$removed"))
  note "the preinstalls stay removed: $(tr '\n' ' ' <<<"$removed")"
fi

missing=()
for name in "${names[@]}"; do
  "$resolver" installed "$name" >/dev/null 2>&1 || missing+=("$name")
done
if (( ${#missing[@]} == 0 )); then
  note "upstream's default packages are all here"
  exit 0
fi

log "upstream's default packages: ${#missing[@]} to install"
note "${missing[*]}"
# One batch first, as apt resolves it best; the resolver stops at the first
# name it cannot install, so a failure is retried one name at a time to
# install the rest and say which ones are left.
if ! "$resolver" add "${missing[@]}"; then
  failed=()
  for name in "${missing[@]}"; do
    "$resolver" installed "$name" >/dev/null 2>&1 || "$resolver" add "$name" || failed+=("$name")
  done
  if (( ${#failed[@]} > 0 )); then
    warn "not installed: ${failed[*]} (the errors above say why); $REPO_DIR/bootstrap.sh 47 tries again"
  fi
fi
