#!/bin/bash
# The channel a machine follows and what it resolves to. Source, do not execute.
#
# Upstream's omarchy-channel-set picks a package ring: stable, rc, edge, or dev
# for a source checkout. Here every install is a checkout, so a channel picks
# the upstream ref the `ubuntu` branch is rebuilt on and the patch series that
# goes on it:
#   stable  the release tag pinned as OMARCHY_TAG_STABLE
#   rc      the tag pinned as OMARCHY_TAG_RC: a pre-release, or the release
#           while no newer pre-release is out, as upstream's rc ring carries
#   edge    upstream's default branch, unpinned
#   dev     a checkout of your own; the updater leaves it alone
# A tag reaches a pin once the port was checked against it
# (omarchy-upstream-check), the way a release only reaches upstream's ring
# once omarchy-pkgs built it.
#
# Needs PORT_DIR (REPO_DIR in the bootstrap). Sets OMARCHY_CHANNEL and
# everything versions.env declares.

PORT_DIR=${PORT_DIR:-${REPO_DIR:?}}
# shellcheck source=../versions.env
source "$PORT_DIR/versions.env"

# The choice lives with the rest of Omarchy's per-user state, since the
# checkout is the user's. Upstream reads it off /etc/pacman.conf.
OMARCHY_CHANNEL_FILE=${OMARCHY_HOME:-$HOME}/.local/state/omarchy/channel

omarchy_channel_valid() {
  case ${1:-} in
    stable | rc | edge | dev) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -z ${OMARCHY_CHANNEL:-} ]]; then
  OMARCHY_CHANNEL=$(cat "$OMARCHY_CHANNEL_FILE" 2>/dev/null) || OMARCHY_CHANNEL=stable
fi
if ! omarchy_channel_valid "$OMARCHY_CHANNEL"; then
  echo "unknown channel '$OMARCHY_CHANNEL': stable, rc, edge or dev ($OMARCHY_CHANNEL_FILE)" >&2
  return 1 2>/dev/null || exit 1
fi

# rc, edge and dev build what the rc ring carries.
case $OMARCHY_CHANNEL in
  rc | edge | dev)
    # shellcheck source=../versions.rc.env
    [[ ! -f $PORT_DIR/versions.rc.env ]] || source "$PORT_DIR/versions.rc.env"
    ;;
esac

# channel_tag [channel]: the pinned tag; nothing on edge and dev.
channel_tag() {
  case ${1:-$OMARCHY_CHANNEL} in
    stable) echo "$OMARCHY_TAG_STABLE" ;;
    rc) echo "$OMARCHY_TAG_RC" ;;
    *) echo "" ;;
  esac
}

# channel_patches [channel]: the series applied on the channel's ref. edge and
# dev build what the rc ring carries, so they take rc's series when there is
# one; a channel without a series of its own takes stable's.
channel_patches() {
  local channel=${1:-$OMARCHY_CHANNEL} candidate
  local -a candidates
  case $channel in
    stable) candidates=(stable) ;;
    rc) candidates=(rc stable) ;;
    *) candidates=("$channel" rc stable) ;;
  esac
  for candidate in "${candidates[@]}"; do
    if [[ -d $PORT_DIR/patches/$candidate ]]; then
      echo "$PORT_DIR/patches/$candidate"
      return 0
    fi
  done
  return 1
}

# channel_series_base [channel]: the tag the series was cut on (recorded by
# omarchy-port-series), where it applies as is. The branch is built there and
# rebased onto the channel's ref: a rebase works on trees, which a blobless
# clone fetches as needed, where `am -3` would look for blobs by hash and find
# none.
channel_series_base() {
  local dir base
  dir=$(channel_patches "${1:-$OMARCHY_CHANNEL}")
  base=$(cat "$dir/base" 2>/dev/null) || base=""
  [[ -n $base ]] || { echo "no base tag recorded in $dir (omarchy-port-series writes it)" >&2; return 1; }
  echo "$base"
}

# series_subjects <series dir>: the subject of each patch, unfolded by git
# mailinfo where format-patch wrapped a long one.
series_subjects() {
  local p
  for p in "$1"/*.patch; do
    git mailinfo /dev/null /dev/null <"$p" | sed -n 's/^Subject: //p'
  done
}

# channel_branch_scan <git dir> <branch> <series dir>: walks the branch down
# from its tip, past the port's commits, to the first commit upstream knows
# (a tag or origin reaches it): the base the branch was built on. Sets
# OMARCHY_BRANCH_BASE to it, OMARCHY_BRANCH_SERIES to how many of the series'
# commits sit above it, OMARCHY_BRANCH_STALE to how many commits the port
# applied from a series since changed (its committer identity marks them;
# they are the port's to drop, not the user's to keep), and
# OMARCHY_BRANCH_FOREIGN to the subjects of commits that are none of these.
# Fails when no upstream commit is within reach.
# shellcheck disable=SC2034  # the OMARCHY_BRANCH_* results are the caller's
channel_branch_scan() {
  local dir=$1 branch=$2 series=$3 sha committer subject
  local -A known=()
  while IFS= read -r subject; do known[$subject]=1; done < <(series_subjects "$series")
  OMARCHY_BRANCH_BASE=""
  OMARCHY_BRANCH_SERIES=0
  OMARCHY_BRANCH_STALE=0
  OMARCHY_BRANCH_FOREIGN=()
  while IFS=$'\t' read -r sha committer subject; do
    if [[ -n ${known[$subject]-} ]]; then
      OMARCHY_BRANCH_SERIES=$((OMARCHY_BRANCH_SERIES + 1))
      continue
    fi
    if [[ $committer == omarchy-ubuntu@localhost ]]; then
      OMARCHY_BRANCH_STALE=$((OMARCHY_BRANCH_STALE + 1))
      continue
    fi
    if [[ -n $(git -C "$dir" for-each-ref --contains "$sha" refs/tags refs/remotes/origin) ]]; then
      OMARCHY_BRANCH_BASE=$sha
      return 0
    fi
    OMARCHY_BRANCH_FOREIGN+=("$subject")
  done < <(git -C "$dir" log -n 100 --format=$'%H\t%ce\t%s' "$branch")
  return 1
}

# upstream_default_branch <git dir>: what origin/HEAD points at (`git remote
# set-head origin --auto` keeps it current); master when it was never set.
upstream_default_branch() {
  local head
  head=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || head=origin/master
  echo "${head#origin/}"
}

# Tags as versions, a pre-release before the release it precedes: v4.5.0-rc1
# sorts under v4.5.0 and above v4.0.6.
channel_tags_sorted() {
  git -C "$1" -c versionsort.suffix=-beta -c versionsort.suffix=-rc tag --list 'v*' --sort=-v:refname
}

# channel_newest <channel> <git dir>: the newest upstream ref the channel
# admits, what a pin is measured against.
channel_newest() {
  case $1 in
    stable) channel_tags_sorted "$2" | grep -v -- '-' | head -n1 ;;
    rc) channel_tags_sorted "$2" | head -n1 ;;
    edge | dev) echo "origin/$(upstream_default_branch "$2")" ;;
  esac
}
