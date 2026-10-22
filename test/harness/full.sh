#!/usr/bin/env bash
# Full bootstrap of the port at a ref of a repository, in a clean Ubuntu 24.04
# container, as far as a container without a session goes (full-test.sh).
#   test/harness/full.sh <port repo dir> <ref> [steps...]   (steps: 10 12 15 20 25 30 40 45)
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$1
ref=$2
shift 2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The ref as the source repository resolves it: a pull request's checkout is
# a detached merge commit that no branch of the clone would name.
git clone -q "$repo" "$work/omarchy-ubuntu" && git -C "$work/omarchy-ubuntu" checkout -q "$(git -C "$repo" rev-parse "$ref")" || exit 2
docker build -q -t omarchy-ubuntu-harness "$here" >/dev/null || exit 2
# Every step's full output outlives the container, under logs/<ref>/.
logs=$here/logs/${ref//\//-}
mkdir -p "$logs"
# apt's package cache and index lists persist across runs: after one good
# fetch the PPAs are only asked for what changed. Docker volumes by default;
# APT_CACHE_DIR=<dir> binds two directories there instead, which is what a CI
# runner can carry from one job to the next. apt's locks live in these
# directories, so runs side by side need their own set: CACHE=<name> picks
# the volumes omarchy-harness-apt-{archives,lists}-<name> (seed them from
# the main pair with `docker run --rm -v <main>:/from:ro -v <copy>:/to
# ubuntu:24.04 cp -a /from/. /to/`).
if [[ -n ${APT_CACHE_DIR:-} ]]; then
  mkdir -p "$APT_CACHE_DIR/archives" "$APT_CACHE_DIR/lists"
  archives=$APT_CACHE_DIR/archives
  lists=$APT_CACHE_DIR/lists
else
  archives=omarchy-harness-apt-archives${CACHE:+-$CACHE}
  lists=omarchy-harness-apt-lists${CACHE:+-$CACHE}
fi
docker run --rm \
  -e STEPS="$*" \
  -e OMARCHY_CHANNEL="${OMARCHY_CHANNEL:-stable}" \
  -v "$archives:/var/cache/apt/archives" \
  -v "$lists:/var/lib/apt/lists" \
  -v "$logs:/tmp/steps" \
  -v "$work/omarchy-ubuntu:/src/omarchy-ubuntu:ro" \
  -v "$here/full-test.sh:/src/full-test.sh:ro" \
  omarchy-ubuntu-harness bash /src/full-test.sh
