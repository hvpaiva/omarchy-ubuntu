#!/bin/bash
# Upstream's default package set, what Omarchy's installer lays down on a new
# machine (omarchy-pkg-defaults from 4.5, install/omarchy-base.packages
# before), through omarchy-pkg-ubuntu: what Ubuntu or the steps before put
# here already is left as it is, a skip recipe stands for what does not apply
# on Ubuntu, the rest comes through its alias or recipe. Like the installer it
# runs at bootstrap, and the preinstalls the user removed stay removed.
#
#   47-base-packages.sh             the set, at bootstrap
#   47-base-packages.sh --release   (the updater, after a release upgrade) what the upgrade took
#   47-base-packages.sh --snapshot  (the updater, on the release it last ran on) the record --release reads
source "${REPO_DIR:?}/lib/common.sh"
need_user
mode=${1:-}

# What dpkg has installed. Written at each update on an unchanged release and
# at the end of a bootstrap, it is what the machine had before the next
# release upgrade.
snapshot=$REPO_DIR/.applied/dpkg-packages
write_snapshot() {
  install -d "$REPO_DIR/.applied"
  dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' | awk '$1 ~ /^.i/ { print $2 }' | LC_ALL=C sort >"$snapshot"
}
if [[ $mode == --snapshot ]]; then
  write_snapshot
  exit 0
fi

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

# Upstream's update never brings the set back, so after a release upgrade
# only what the upgrade took comes back: dpkg's packages, the only kind an
# upgrade removes, and of those the ones the machine had before it, where the
# record says so (one the user removed stays removed). Without a record, every
# name dpkg holds.
upgrade_took() {
  local packages
  packages=$("$resolver" dpkg-names "$1" 2>/dev/null)
  [[ -n $packages ]] || return 1
  [[ ! -f $snapshot ]] || grep -qxF -f <(printf '%s\n' "$packages") "$snapshot"
}

missing=()
for name in "${names[@]}"; do
  "$resolver" installed "$name" >/dev/null 2>&1 && continue
  [[ $mode != --release ]] || upgrade_took "$name" || continue
  missing+=("$name")
done
if (( ${#missing[@]} == 0 )); then
  if [[ $mode == --release ]]; then
    note "nothing of upstream's default packages to bring back after the release upgrade"
  else
    note "upstream's default packages are all here"
    write_snapshot
  fi
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
[[ $mode == --release ]] || write_snapshot
