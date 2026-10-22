#!/usr/bin/env bash
# Runs inside the harness container as `tester`: the bootstrap on a clean
# Ubuntu 24.04 as far as a container without a session goes (apt, debs, Qt,
# toolchains, checkout, Quickshell, tools), then the versions that came out.
set -u

export HOME=/home/tester
PORT=$HOME/.local/share/omarchy-ubuntu
# The source is bind-mounted from the host's user, not the container's (a CI
# runner is uid 1001, tester is 1000): git would refuse it as dubious. For a
# clone's source git matches the git directory itself, not the work tree.
git config --global --add safe.directory /src/omarchy-ubuntu/.git
git clone -q /src/omarchy-ubuntu "$PORT"
cd "$PORT" || exit 2
export DEBIAN_FRONTEND=noninteractive OMARCHY_ROOT_VIA=sudo
export OMARCHY_CHANNEL=${OMARCHY_CHANNEL:-stable}

logs=/tmp/steps
mkdir -p "$logs"
status=0
for step in ${STEPS:-10 12 15 20 25 30 40 45}; do
  start=$(date +%s)
  if ./bootstrap.sh "$step" >"$logs/step-$step.log" 2>&1; then
    echo "OK    step $step ($(( $(date +%s) - start ))s)"
  else
    echo "FAIL  step $step ($(( $(date +%s) - start ))s)"
    tail -30 "$logs/step-$step.log" | sed 's/^/      /'
    status=1
  fi
done

echo "== versions"
# Qt apps print a locale warning before anything else under LANG=C.
export LANG=C.UTF-8 PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/mise/shims:$PATH"
for b in quickshell tensaku ttfx hyprpicker xdg-terminal-exec gpu-screen-recorder aether hyprland-preview-share-picker omacalc omawrite omacut omasnap owe cliamp herdr gum mise; do
  if command -v "$b" >/dev/null 2>&1; then
    printf '%-32s %s\n' "$b" "$("$b" --version 2>&1 | head -1 | cut -c1-70)"
  else
    printf '%-32s missing\n' "$b"
  fi
done
echo "== checkout"; git -C "$HOME/.local/share/omarchy" describe --tags; git -C "$HOME/.local/share/omarchy" rev-list --count "$(git -C "$HOME/.local/share/omarchy" describe --tags --abbrev=0)..HEAD"
exit $status
