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

# Every package name the checkout can hand its package helpers (lib/catalog.py),
# through omarchy-pkg-ubuntu's own lookup: a recipe or an alias, an apt
# candidate, or already here, which is what the steps above put on the machine
# (so the ones that do, 15 to 45, must have run). A name the checkout installs
# and that resolves to none of them fails the run; one it only checks for or
# removes is listed.
checkout=$HOME/.local/share/omarchy
echo "== package catalog"
steps=" ${STEPS:-10 12 15 20 25 30 40 45} "
missing_steps=""
for s in 15 25 30 40 45; do
  [[ $steps == *" $s "* ]] || missing_steps+=" $s"
done
if [[ -n $missing_steps ]]; then
  echo "not read: steps$missing_steps did not run"
elif [[ ! -f $checkout/bin/omarchy-pkg-ubuntu ]]; then
  echo "FAIL  no omarchy-pkg-ubuntu in the checkout"
  status=1
else
  resolver=$(mktemp)
  sed '/^command=\${1:-}$/,$d' "$checkout/bin/omarchy-pkg-ubuntu" >"$resolver"
  unresolved=$(
    # shellcheck disable=SC1090
    source "$resolver"
    set +e
    while IFS=$'\t' read -r name contexts; do
      recipe_of "$name" >/dev/null && continue
      for n in $(apt_names "$name"); do
        apt_candidate "$n" && continue 2
      done
      installed "$name" && continue
      printf '%s\t%s\n' "$name" "$contexts"
    done < <(python3 lib/catalog.py "$checkout" |
      awk -F'\t' '$2 != "unresolved" && !seen[$1 FS $2]++ { c[$1] = c[$1] (c[$1] ? "," : "") $2 } END { for (n in c) print n "\t" c[n] }' | sort)
  )
  if [[ -z $unresolved ]]; then
    echo "every name resolves"
  fi
  while IFS=$'\t' read -r name contexts; do
    [[ -n $name ]] || continue
    if grep -qvxE 'present|missing|drop|remove' < <(tr ',' '\n' <<<"$contexts"); then
      echo "FAIL  $name ($contexts): no recipe, alias, apt candidate or install here"
      status=1
    else
      echo "      $name ($contexts): no source, only checked for or removed"
    fi
  done <<<"$unresolved"
fi
exit $status
