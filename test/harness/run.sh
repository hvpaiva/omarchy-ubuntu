#!/usr/bin/env bash
# The updater and channel scenarios (test.sh) in a clean Ubuntu container, on
# the port at a ref of a repository.
#   test/harness/run.sh <port repo dir> [ref]      (ref: HEAD)
# UBUNTU=26.04 runs them on that release (24.04 otherwise), in an image of its
# own; APT_MIRROR=<url> builds the image's apt sources on a mirror.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$1
ref=${2:-HEAD}
release=${UBUNTU:-24.04}
image=omarchy-ubuntu-harness
[[ $release == 24.04 ]] || image+=-$release
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The ref as the source repository resolves it: a pull request's checkout is
# a detached merge commit that no branch of the clone would name.
git clone -q "$repo" "$work/omarchy-ubuntu" && git -C "$work/omarchy-ubuntu" checkout -q "$(git -C "$repo" rev-parse "$ref")" || exit 2
docker build -q -t "$image" --build-arg UBUNTU="$release" --build-arg APT_MIRROR="${APT_MIRROR:-}" "$here" >/dev/null || exit 2
docker run --rm \
  -v "$work/omarchy-ubuntu:/src/omarchy-ubuntu:ro" \
  -v "$here/test.sh:/src/test.sh:ro" \
  "$image" bash /src/test.sh
