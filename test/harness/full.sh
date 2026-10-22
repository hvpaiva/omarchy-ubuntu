#!/usr/bin/env bash
# Full bootstrap of the port at a ref of a repository, in a clean Ubuntu
# container, as far as a container without a session goes (full-test.sh).
#   test/harness/full.sh <port repo dir> <ref> [steps...]   (steps: 10 12 15 20 25 30 40 45)
# UBUNTU=26.04 runs it on that release (24.04 otherwise), in an image of its
# own; APT_MIRROR=<url> builds the image's apt sources on a mirror.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$1
ref=$2
shift 2
release=${UBUNTU:-24.04}
image=omarchy-ubuntu-harness
# What a run on another release keeps apart from 24.04's: image, logs, apt cache.
apart=""
[[ $release == 24.04 ]] || apart=-$release
image+=$apart
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The ref as the source repository resolves it: a pull request's checkout is
# a detached merge commit that no branch of the clone would name.
commit=$(git -C "$repo" rev-parse "$ref") || exit 2
git clone -q "$repo" "$work/omarchy-ubuntu" && git -C "$work/omarchy-ubuntu" checkout -q "$commit" || exit 2
docker build -q -t "$image" --build-arg UBUNTU="$release" --build-arg APT_MIRROR="${APT_MIRROR:-}" "$here" >/dev/null || exit 2
# Every step's full output outlives the container, under logs/<channel>-<commit>/
# (logs/<release>-<channel>-<commit>/ off 24.04): the ref as typed (HEAD, a
# branch) names neither of the two things a run tests.
# full-test.sh writes there as tester (uid 1000); on a CI runner the host's
# user is another uid, and a bind mount keeps the host's ownership.
logs=$here/logs/${apart#-}${apart:+-}${OMARCHY_CHANNEL:-stable}-${commit:0:12}
mkdir -p "$logs" && chmod o+w "$logs"
# apt's package cache and index lists persist across runs: after one good
# fetch the PPAs are only asked for what changed. Docker volumes by default;
# APT_CACHE_DIR=<dir> binds two directories there instead, which is what a CI
# runner can carry from one job to the next. apt's locks live in these
# directories, so runs side by side need their own set: CACHE=<name> picks
# the volumes omarchy-harness-apt-{archives,lists}-<name> (seed them from
# the main pair with `docker run --rm -v <main>:/from:ro -v <copy>:/to
# ubuntu:24.04 cp -a /from/. /to/`). Another release has volumes of its own
# (omarchy-harness-apt-archives-26.04 and so on).
if [[ -n ${APT_CACHE_DIR:-} ]]; then
  mkdir -p "$APT_CACHE_DIR/archives" "$APT_CACHE_DIR/lists"
  archives=$APT_CACHE_DIR/archives
  lists=$APT_CACHE_DIR/lists
else
  archives=omarchy-harness-apt-archives$apart${CACHE:+-$CACHE}
  lists=omarchy-harness-apt-lists$apart${CACHE:+-$CACHE}
fi
docker run --rm \
  -e STEPS="$*" \
  -e OMARCHY_CHANNEL="${OMARCHY_CHANNEL:-stable}" \
  -v "$archives:/var/cache/apt/archives" \
  -v "$lists:/var/lib/apt/lists" \
  -v "$logs:/tmp/steps" \
  -v "$work/omarchy-ubuntu:/src/omarchy-ubuntu:ro" \
  -v "$here/full-test.sh:/src/full-test.sh:ro" \
  "$image" bash /src/full-test.sh
