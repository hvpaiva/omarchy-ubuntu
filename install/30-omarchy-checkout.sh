#!/bin/bash
# The Omarchy checkout, in upstream's "dev link" layout: the tree lives under
# ~/.local/share/omarchy and /usr/share/omarchy points at it (done in 55-root.sh).
# The `ubuntu` branch carries the port's patches on top of the channel's ref
# (lib/channel.sh): dpkg-based package guards, apt-backed pkg helpers, update
# hand-off, logout without uwsm. Either use your fork (OMARCHY_FORK) or apply
# the series under ./patches locally.
# shellcheck source=../lib/common.sh
source "${REPO_DIR:?}/lib/common.sh"
need_user

if [[ ! -d $OMARCHY_PATH/.git ]]; then
  log "cloning Omarchy"
  git clone --quiet --filter=blob:none "$OMARCHY_REPO" "$OMARCHY_PATH"
fi

cd "$OMARCHY_PATH"
git fetch --quiet --tags origin
git remote set-head origin --auto >/dev/null 2>&1 || true
target=$(channel_tag)
[[ -n $target ]] || target=$(channel_newest "$OMARCHY_CHANNEL" "$OMARCHY_PATH")
series=$(channel_patches)

if git show-ref --verify --quiet "refs/heads/$OMARCHY_BRANCH"; then
  git checkout --quiet "$OMARCHY_BRANCH"
  base=$(git describe --tags --abbrev=0)
  note "branch $OMARCHY_BRANCH already present ($(git rev-parse --short HEAD), $(git rev-list --count "$base..HEAD") patches over $base); omarchy-update-ubuntu moves it"
elif [[ -n $OMARCHY_FORK ]]; then
  log "fetching $OMARCHY_BRANCH from $OMARCHY_FORK"
  git remote add fork "$OMARCHY_FORK" 2>/dev/null || git remote set-url fork "$OMARCHY_FORK"
  git fetch --quiet fork "$OMARCHY_BRANCH"
  git checkout --quiet -b "$OMARCHY_BRANCH" "fork/$OMARCHY_BRANCH"
else
  # The series goes on the tag it was cut on, then the branch moves to the
  # channel's ref by rebase, as omarchy-update-ubuntu does. The committer is
  # the port's, which marks the commits as its own for the updater and gets a
  # machine without a git identity through; the author stays the patch's. It
  # goes in the environment, where a GIT_COMMITTER_* of the user's would
  # otherwise win over any -c.
  export GIT_COMMITTER_NAME=omarchy-ubuntu GIT_COMMITTER_EMAIL=omarchy-ubuntu@localhost
  series_base=$(channel_series_base)
  log "creating $OMARCHY_BRANCH from $series_base and applying ${series#"$REPO_DIR/"}"
  git checkout --quiet -b "$OMARCHY_BRANCH" "$series_base"
  # A patch or a move that fails leaves nothing behind: the branch goes, so
  # the next run starts over instead of finding it "already present" half done.
  start_over() {
    git am --abort 2>/dev/null || true
    git rebase --abort 2>/dev/null || true
    git checkout --quiet --detach
    git branch --quiet -D "$OMARCHY_BRANCH"
    die "$1"
  }
  # The commits are the port's, so the user's signing setup stays out of them.
  for p in "$series"/*.patch; do
    git -c commit.gpgsign=false am --quiet "$p" || start_over "$(basename "$p") does not apply on $series_base"
    note "applied $(basename "$p")"
  done
  if [[ $target != "$series_base" ]]; then
    log "moving $OMARCHY_BRANCH onto $target ($OMARCHY_CHANNEL channel)"
    git -c commit.gpgsign=false rebase --quiet --onto "$target" "$series_base" "$OMARCHY_BRANCH" ||
      start_over "the series does not rebase onto $target; see omarchy-upstream-check --channel $OMARCHY_CHANNEL --target $target"
  fi
fi

note "omarchy $(git describe --tags --always) on the $OMARCHY_CHANNEL channel"
