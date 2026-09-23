#!/bin/bash
# The Omarchy checkout, in upstream's "dev link" layout: the tree lives under
# ~/.local/share/omarchy and /usr/share/omarchy points at it (done in 55-root.sh).
# The `ubuntu` branch carries the port's patches on top of the pinned tag:
# dpkg-based package guards, apt-backed pkg helpers, update hand-off, logout
# without uwsm. Either use your fork (OMARCHY_FORK) or apply ./patches locally.
source "${REPO_DIR:?}/lib/common.sh"
need_user

if [[ ! -d $OMARCHY_PATH/.git ]]; then
  log "cloning Omarchy $OMARCHY_TAG"
  git clone --quiet --filter=blob:none "$OMARCHY_REPO" "$OMARCHY_PATH"
fi

cd "$OMARCHY_PATH"
git fetch --quiet --tags origin

if git show-ref --verify --quiet "refs/heads/$OMARCHY_BRANCH"; then
  git checkout --quiet "$OMARCHY_BRANCH"
  note "branch $OMARCHY_BRANCH already present ($(git rev-parse --short HEAD), $(git rev-list --count "$OMARCHY_TAG..HEAD") patches over $OMARCHY_TAG)"
elif [[ -n $OMARCHY_FORK ]]; then
  log "fetching $OMARCHY_BRANCH from $OMARCHY_FORK"
  git remote add fork "$OMARCHY_FORK" 2>/dev/null || git remote set-url fork "$OMARCHY_FORK"
  git fetch --quiet fork "$OMARCHY_BRANCH"
  git checkout --quiet -b "$OMARCHY_BRANCH" "fork/$OMARCHY_BRANCH"
else
  log "creating $OMARCHY_BRANCH from $OMARCHY_TAG and applying ./patches"
  git checkout --quiet -b "$OMARCHY_BRANCH" "$OMARCHY_TAG"
  for p in "$REPO_DIR"/patches/*.patch; do
    [[ -f $p ]] || continue
    git am --quiet "$p"
    note "applied $(basename "$p")"
  done
fi

note "omarchy $(git describe --tags --always)"
