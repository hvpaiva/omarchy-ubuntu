#!/usr/bin/env bash
# Runs inside the harness container as `tester`. Exercises the bootstrap's
# checkout step per channel, the channel commands, and the updater's branch
# rebuild, migration table, local-commit guard, channel switch and self-update.
set -u

export HOME=/home/tester
PORT=$HOME/.local/share/omarchy-ubuntu
# The source is bind-mounted from the host's user, not the container's (a CI
# runner is uid 1001, tester is 1000): git would refuse it as dubious. For a
# clone's source git matches the git directory itself, not the work tree.
git config --global --add safe.directory /src/omarchy-ubuntu/.git
export OMARCHY_PATH=$HOME/.local/share/omarchy
export OMARCHY_UBUNTU_DIR=$PORT
export OMARCHY_UPDATE_UNATTENDED=1
# The tool steps (Qt, Quickshell, the apps) are the full harness's business.
export OMARCHY_UPDATE_TOOLS=0
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@localhost GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@localhost

pass=0; fail=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
ko() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { # check <name> <command...>: pass when the command exits 0
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else ko "$name"; fi
}
expect() { # expect <name> <wanted> <got>
  if [[ $2 == "$3" ]]; then ok "$1"; else ko "$1 (wanted '$2', got '$3')"; fi
}

# Shims for what a container has no session for.
mkdir -p "$HOME/shims"
for s in systemctl hyprctl Hyprland journalctl omarchy-restart-shell omarchy-update-stay-awake omarchy-show-done; do
  printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/$s"; chmod +x "$HOME/shims/$s"
done
export PATH="$HOME/shims:$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"

# The port, as a clone with a remote the self-update test can push to. Whatever
# the source had checked out (a branch, a pull request's detached merge
# commit), the port under test sits on main, as an install does.
git init -q --bare -b main /tmp/port.git
git clone -q /src/omarchy-ubuntu "$PORT"
git -C "$PORT" checkout -q -B main
git -C "$PORT" remote set-url origin /tmp/port.git
git -C "$PORT" push -q -u origin main || { echo "the port's remote refused the push (a shallow source?)"; exit 2; }
head=$(git -C "$PORT" rev-parse --short HEAD)
echo "port at $head, branch $(git -C "$PORT" branch --show-current)"

# The pins the branch ships, and a second tag to move between.
BASE=$(sed -n 's/^OMARCHY_TAG_STABLE=\${OMARCHY_TAG_STABLE:-\(v[^}]*\)}.*/\1/p' "$PORT/versions.env")
RC_BASE=$(sed -n 's/^OMARCHY_TAG_RC=\${OMARCHY_TAG_RC:-\(v[^}]*\)}.*/\1/p' "$PORT/versions.env")
RC_VERSION=${RC_BASE#v}; RC_VERSION=${RC_VERSION/-rc/rc}   # spelled as upstream's package
if [[ $BASE == v4.0.6 ]]; then NEXT=v4.0.5; else NEXT=v4.0.6; fi
echo "stable pin $BASE, rc pin $RC_BASE, moving to $NEXT"
RC_PATCHES=$(ls "$PORT"/patches/rc/*.patch | wc -l)
pin() { # pin <tag>: commit a stable pin on the port and publish it, as a maintainer would
  sed -i "s/OMARCHY_TAG_STABLE:-v[0-9.]*/OMARCHY_TAG_STABLE:-$1/" "$PORT/versions.env"
  git -C "$PORT" commit -qam "pin $1" && git -C "$PORT" push -q origin HEAD:main
}
mark_done() { # mark_done <tag>: every migration the tag ships, as a fresh install's state
  mkdir -p "$HOME/.local/state/omarchy/migrations"
  git -C "$OMARCHY_PATH" ls-tree --name-only "$1" -- migrations/ | while read -r m; do touch "$HOME/.local/state/omarchy/migrations/$(basename "$m")"; done
}
onfail() { # onfail <log>: the tail of an updater log when a check just failed
  echo "----- $1"; tail -25 "$1" | sed 's/^/      /'; echo "-----"
}

echo "== S1 stable bootstrap, step 30"
(cd "$PORT" && REPO_DIR=$PORT ./bootstrap.sh 30) >/tmp/s1.log 2>&1 || { ko "S1 bootstrap 30 exit (see log)"; tail -20 /tmp/s1.log; }
expect "S1 channel file" stable "$(cat "$HOME/.local/state/omarchy/channel" 2>/dev/null)"
expect "S1 branch" ubuntu "$(git -C "$OMARCHY_PATH" branch --show-current)"
expect "S1 base tag" "$BASE" "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)"
expect "S1 patches on top" 13 "$(git -C "$OMARCHY_PATH" rev-list --count "$BASE..ubuntu")"
expect "S1 bootstrap 30 is idempotent" 0 "$( (cd "$PORT" && REPO_DIR=$PORT ./bootstrap.sh 30) >/dev/null 2>&1; echo $?)"
(cd "$PORT" && REPO_DIR=$PORT ./bootstrap.sh 80) >/dev/null 2>&1

echo "== S2 channel commands"
expect "S2 current" stable "$(omarchy-channel-ubuntu current)"
expect "S2 version" "${BASE#v}" "$(omarchy-channel-ubuntu version)"
expect "S2 target" "$BASE" "$(omarchy-channel-ubuntu target)"
expect "S2 upstream omarchy-version hands over" "${BASE#v}" "$(omarchy-version)"
expect "S2 upstream omarchy-channel-current hands over" stable "$(omarchy-channel-current)"
out=$(omarchy-update-available); st=$?
expect "S2 update-available: nothing" "1:Omarchy is up to date" "$st:$out"
expect "S2 unknown channel refused" 1 "$(OMARCHY_CHANNEL=bogus omarchy-channel-ubuntu current >/dev/null 2>&1; echo $?)"

echo "== S3 the stable pin moves to $NEXT"
# Every migration either tag ships is marked done: the container has none of
# what they install, and the updater's migration logic gets its own scenario.
mark_done "$BASE"; mark_done "$NEXT"; mark_done "$RC_BASE"
pin "$NEXT"
out=$(omarchy-update-available); st=$?
expect "S3 update-available sees the pin" "0:omarchy ${BASE#v} -> ${NEXT#v}" "$st:$out"
# A grant the pre-4.5 helper wrote and a stranger under its prefix, for the port's migration.
echo "tester ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-omarchy-nopasswd-tester >/dev/null
echo "tester ALL=(ALL) NOPASSWD: /usr/bin/true" | sudo tee /etc/sudoers.d/99-omarchy-nopasswd-odd >/dev/null
sudo chmod 440 /etc/sudoers.d/99-omarchy-nopasswd-tester /etc/sudoers.d/99-omarchy-nopasswd-odd
# A shell restarted by the update, and a journal where only the one it
# replaced (another pid) logged errors, as the old shell does while it
# reloads the new tree's files.
printf '#!/bin/bash\necho "[{\\"pid\\":4242,\\"config_path\\":\\"%s/shell/shell.qml\\"}]"\n' "$OMARCHY_PATH" >"$HOME/shims/quickshell"
printf '#!/bin/bash\n[[ " $* " == *" _PID=4242 "* ]] && exit 0\necho "file:///x/Dock.qml:347:5: ShellIpc is not a type"\n' >"$HOME/shims/journalctl"
chmod +x "$HOME/shims/quickshell" "$HOME/shims/journalctl"
omarchy-update-ubuntu -y >/tmp/s3.log 2>&1; st=$?
expect "S3 updater exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s3.log
grep -q "The shell logged QML errors" /tmp/s3.log && ko "S3 the replaced shell's errors are not reported" || ok "S3 the replaced shell's errors are not reported"
pieces=$(grep -n 'Pieces outside the checkout' /tmp/s3.log | head -1 | cut -d: -f1)
migrations=$(grep -n $'\e\\[32mMigrations' /tmp/s3.log | head -1 | cut -d: -f1)
[[ -n $pieces && -n $migrations ]] && (( pieces < migrations )) && ok "S3 root pieces reapplied before the migrations" || ko "S3 root pieces reapplied before the migrations (lines $pieces, $migrations)"
# Before 4.5 the port's migrations have nothing to stand in for: all pending.
check "S3 the old helper's grant stays on 4.0.x" sudo test -f /etc/sudoers.d/99-omarchy-nopasswd-tester
expect "S3 no port migration recorded before 4.5" 0 "$(ls "$PORT/.applied/migrations" 2>/dev/null | wc -l)"
expect "S3 pending port migrations say so" "$(find "$PORT/migrations" -name '*.sh' ! -name '*-root.sh' | wc -l)" "$(grep -c "left pending, not applicable yet" /tmp/s3.log)"
expect "S3 base tag" "$NEXT" "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)"
expect "S3 patches on top" 13 "$(git -C "$OMARCHY_PATH" rev-list --count "$NEXT..ubuntu")"
expect "S3 version" "${NEXT#v}" "$(omarchy-version)"
expect "S3 clean tree" "" "$(git -C "$OMARCHY_PATH" status --porcelain)"
check "S3 browser policy helper reapplied" test -x /usr/bin/omarchy-theme-set-browser-policy
check "S3 sudoers rule reapplied" sudo test -f /etc/sudoers.d/omarchy-theme-browser
check "S3 system tweak installed" test -f /etc/sysctl.d/99-omarchy-sysctl.conf
check "S3 port commands linked" test -L "$HOME/.local/bin/omarchy-channel-ubuntu"
grep -q "Migrations" /tmp/s3.log && grep -q "None pending" /tmp/s3.log && ok "S3 no migration pending" || ko "S3 migrations step"

echo "== S4 migration table (1790397381 exits 0 on its own; 1791403252 reorders pacman.conf)"
rm -f "$HOME/.local/state/omarchy/migrations/1790397381.sh" "$HOME/.local/state/omarchy/migrations/1791403252.sh"
sed -i '/^OMARCHY_MIGRATIONS_ARCH_ONLY=(/,/^)/{/1791403252.sh/d}' "$PORT/lib/migrations.sh"
git -C "$PORT" commit -qam "table: without 1791403252" >/dev/null 2>&1 || true
omarchy-update-ubuntu -y >/tmp/s4a.log 2>&1 || onfail /tmp/s4a.log
check "S4 plain migration ran" test -f "$HOME/.local/state/omarchy/migrations/1790397381.sh"
check "S4 unlisted Arch migration left pending" test ! -f "$HOME/.local/state/omarchy/migrations/1791403252.sh"
grep -q "does not list it yet" /tmp/s4a.log && ok "S4 unlisted Arch migration flagged" || ko "S4 unlisted Arch migration flagged"
sed -i 's/^OMARCHY_MIGRATIONS_ARCH_ONLY=(/OMARCHY_MIGRATIONS_ARCH_ONLY=(\n  1791403252.sh/' "$PORT/lib/migrations.sh"
git -C "$PORT" commit -qam "table: 1791403252 is Arch-only"
omarchy-update-ubuntu -y >/tmp/s4b.log 2>&1 || onfail /tmp/s4b.log
check "S4 listed Arch migration marked done" test -f "$HOME/.local/state/omarchy/migrations/1791403252.sh"
grep -q "Arch-only, marked done" /tmp/s4b.log && ok "S4 marked-done message" || ko "S4 marked-done message"

echo "== S5 a commit of the user's own on the branch"
git -C "$OMARCHY_PATH" commit -q --allow-empty -m "my own change"
pin "$BASE"
omarchy-update-ubuntu -y >/tmp/s5.log 2>&1; st=$?
expect "S5 updater refuses" 1 "$st"
[[ $st == 1 ]] || onfail /tmp/s5.log
grep -q "neither upstream's nor the port's series" /tmp/s5.log && ok "S5 names the foreign commit" || { ko "S5 names the foreign commit"; onfail /tmp/s5.log; }
expect "S5 branch untouched" "$NEXT" "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)"
git -C "$OMARCHY_PATH" reset -q --hard HEAD~1
# This time the shell that just started is the one that logged the error.
printf '#!/bin/bash\n[[ " $* " == *" _PID=4242 "* ]] || exit 0\necho "file:///x/Dock.qml:347:5: ShellIpc is not a type"\n' >"$HOME/shims/journalctl"
omarchy-update-ubuntu -y >/tmp/s5b.log 2>&1; st=$?
expect "S5 updater goes through once removed" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s5b.log
expect "S5 version" "${BASE#v}" "$(omarchy-version)"
grep -q "ShellIpc is not a type" /tmp/s5b.log && ok "S5 the new shell's errors are reported" || ko "S5 the new shell's errors are reported"
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/journalctl"

echo "== S15 a rebase an updater from before the channels left in progress"
GIT_SEQUENCE_EDITOR="sed -i 1s/^pick/edit/" git -C "$OMARCHY_PATH" rebase -q -i HEAD~1 >/dev/null 2>&1
omarchy-update-ubuntu -y >/tmp/s15.log 2>&1; st=$?
expect "S15 updater stops" 1 "$st"
grep -q "rebase --abort" /tmp/s15.log && ok "S15 names the way out" || { ko "S15 names the way out"; onfail /tmp/s15.log; }
git -C "$OMARCHY_PATH" rebase --abort
omarchy-update-ubuntu -y >/tmp/s15b.log 2>&1; st=$?
expect "S15 updater goes through once aborted" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s15b.log

echo "== S6 channel switch"
pin "$NEXT"
# For the port's mise wrappers migration, which 4.5's declarations unlock: a
# mise that does nothing, a wrapper in the port's form and one the user edited.
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/mise"; chmod +x "$HOME/shims/mise"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "aqua:openai/codex" || exit 1\nbin_path=$(mise which --tool "aqua:openai/codex" "codex" 2>/dev/null) || bin_path="codex"\nexec mise x "aqua:openai/codex" -- "$bin_path" "$@"\n' >"$HOME/.local/bin/codex"
printf '#!/bin/bash\n# mine\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "aqua:anthropics/claude-code" || exit 1\nbin_path=$(mise which --tool "aqua:anthropics/claude-code" "claude" 2>/dev/null) || bin_path="claude"\nexec mise x "aqua:anthropics/claude-code" -- "$bin_path" "$@"\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/codex" "$HOME/.local/bin/claude"
# Upstream's 1788163635 pending: it passes on the marker the port's migration writes first.
# Upstream's 1791382872 pending too: the port's wrapper retirement waits for it.
rm -f "$HOME/.local/state/omarchy/migrations/1788163635.sh" "$HOME/.local/state/omarchy/migrations/1791382872.sh"
# An autostart.lua from before 4.5 that the user extended, for the port's owed migration.
mkdir -p "$HOME/.config/hypr"
sed 's/ owed\.service"/ my-thing.service"/' "$PORT/config/hypr/autostart.lua" >"$HOME/.config/hypr/autostart.lua"
# A file of the admin's at a path 4.5 ships and 4.0.x does not: kept beside while on rc, back on the switch back.
sudo mkdir -p /etc/mpv
echo "# the admin's" | sudo tee /etc/mpv/mpv.conf >/dev/null
# The update inhibitor's state as 4.0's leaves it under Ubuntu's umask 002,
# which 4.5's refuses; and an inhibitor that tells which umask it ran under.
inhibitor_state=${XDG_RUNTIME_DIR:-/tmp/omarchy-$UID}/omarchy-update-stay-awake
(umask 002 && mkdir -p "$inhibitor_state" && echo 4242 >"$inhibitor_state/inhibit-pid")
printf '#!/bin/bash\numask >>"$HOME/stay-awake.umask"\n' >"$HOME/shims/omarchy-update-stay-awake"
rm -f "$HOME/stay-awake.umask"
# Under Ubuntu's umask, as a desktop session runs it (a container's is 022).
(umask 002 && omarchy-channel-ubuntu set rc) >/tmp/s6.log 2>&1; st=$?
expect "S6 set rc exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s6.log
expect "S6 current" rc "$(omarchy-channel-current)"
expect "S6 rc pin applied" "$RC_BASE" "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)"
expect "S6 rc patches on top" "$RC_PATCHES" "$(git -C "$OMARCHY_PATH" rev-list --count "$RC_BASE..ubuntu")"
expect "S6 version" "$RC_VERSION" "$(omarchy-version)"
check "S6 mise declarations installed by step 57" test -f /etc/mise/conf.d/omarchy-tools.toml
check "S6 locale helper copied" test -x /usr/bin/omarchy-locale-generate
check "S6 locale sudoers rule" sudo test -f /etc/sudoers.d/omarchy-locale-generate
check "S6 port-form wrapper retired" test ! -e "$HOME/.local/bin/codex"
check "S6 edited wrapper kept" test -f "$HOME/.local/bin/claude"
check "S6 mise wrappers migration recorded" test -f "$PORT/.applied/migrations/1792592500-mise-wrappers.sh"
up=$(grep -n "Running migration (1791382872)" /tmp/s6.log | head -1 | cut -d: -f1)
port=$(grep -n "Ran port migration (1792592500-mise-wrappers)" /tmp/s6.log | head -1 | cut -d: -f1)
[[ -n $up && -n $port ]] && (( up < port )) && ok "S6 port wrapper retirement after upstream's" || ko "S6 port wrapper retirement after upstream's (lines $up, $port)"
check "S6 port migration removed the old helper's grant" sudo test ! -e /etc/sudoers.d/99-omarchy-nopasswd-tester
check "S6 port migration quarantined the stranger as upstream does" sudo sh -c 'grep -qx 99-omarchy-nopasswd-odd /var/lib/omarchy/sudoers-quarantine/*/name && test -f /var/lib/omarchy/sudoers-quarantine/*/policy'
check "S6 port migration wrote the 4.5 helper's marker" test -f /var/lib/omarchy/migrations/1788163635
check "S6 sudo migration recorded" test -f "$PORT/.applied/migrations/1792592191-passwordless-sudo-legacy.sh"
grep -q 'voxtype.service owed.service my-thing.service' "$HOME/.config/hypr/autostart.lua" && ok "S6 autostart.lua gained owed.service, the user's entry kept" || ko "S6 autostart.lua gained owed.service, the user's entry kept"
check "S6 fcitx5 glyphs fetched before the theme migration" test -s /usr/share/fcitx5/themes/default/prev.svg
check "S6 the admin's mpv.conf kept beside upstream's" sudo sh -c 'cmp -s /etc/mpv/mpv.conf "$1" && grep -qx "# the admin.s" /etc/mpv/mpv.conf.bak-omarchy' _ "$OMARCHY_PATH/etc/mpv/mpv.conf"
check "S6 upstream 1788163635 ran on the marker" test -f "$HOME/.local/state/omarchy/migrations/1788163635.sh"
grep -q "Running migration (1788163635)" /tmp/s6.log && ok "S6 upstream 1788163635 ran, not marked" || ko "S6 upstream 1788163635 ran, not marked"
# No Cam Link in a container: the port's migration has nothing to do and upstream's is marked.
check "S6 Cam Link migration recorded, nothing installed without one" sh -c "test -f '$PORT/.applied/migrations/1792636073-camlink-4k.sh' && test -f '$HOME/.local/state/omarchy/migrations/1788862626.sh' && test ! -e /etc/modprobe.d/zz-omarchy-camlink-4k.conf"
# 4.5's passwordless sudo: the packaged copies, and the helper's root actions
# through them. A container has no systemd, so a temporary grant stops at its
# expiry timer, past the lock and the boot cleanup check that refused it before.
check "S6 passwordless sudo's packaged copies" sh -c 'for f in omarchy-sudo-passwordless omarchy-security-functions omarchy-shell; do cmp -s "$1/bin/$f" "/usr/bin/$f" && test "$(stat -c %U "/usr/bin/$f")" = root || exit 1; done' _ "$OMARCHY_PATH"
uid=$(id -u)
{ sudo /usr/bin/omarchy-sudo-passwordless __enable "$uid" permanent; } >/tmp/s6p.log 2>&1; st=$?
expect "S6 permanent passwordless grant published" "0:yes" "$st:$(sudo test -f "/etc/sudoers.d/99-omarchy-permanent-nopasswd-$uid" && echo yes)"
sudo /usr/bin/omarchy-sudo-passwordless __status "$uid" >/dev/null 2>&1; expect "S6 passwordless status active" 0 "$?"
sudo /usr/bin/omarchy-sudo-passwordless __disable "$uid" >/dev/null 2>&1; st=$?
expect "S6 passwordless grant revoked" "0:gone" "$st:$(sudo test -e "/etc/sudoers.d/99-omarchy-permanent-nopasswd-$uid" || echo gone)"
# The expiry timer is the last step before publication: a stand-in that
# records its arguments and fails shows the helper got past the lock, the
# boot cleanup check and visudo, and that a failed timer publishes nothing.
[[ -e /usr/bin/systemd-run ]] && sudo mv /usr/bin/systemd-run /usr/bin/systemd-run.real
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>/tmp/systemd-run.args\nexit 1\n' | sudo tee /usr/bin/systemd-run >/dev/null
sudo chmod 755 /usr/bin/systemd-run
{ sudo /usr/bin/omarchy-sudo-passwordless __enable "$uid" 15; } >/tmp/s6t.log 2>&1
grep -q -- "--on-calendar=@[0-9]* .* __expire $uid" /tmp/systemd-run.args 2>/dev/null && ok "S6 temporary grant reaches its expiry timer" || { ko "S6 temporary grant reaches its expiry timer"; onfail /tmp/s6t.log; }
check "S6 the failed temporary grant left nothing" sudo sh -c "! ls /etc/sudoers.d/ | grep -q nopasswd"
sudo rm -f /usr/bin/systemd-run
[[ -e /usr/bin/systemd-run.real ]] && sudo mv /usr/bin/systemd-run.real /usr/bin/systemd-run
# Upstream's own suites for the helper, against the series' copy: one
# assertion reads "no packaged hook, no timed grant" as the boot rule's case.
# noble's systemd-tmpfiles (255) has no --inline, which one of them uses.
if ! /usr/bin/systemd-tmpfiles --help 2>/dev/null | grep -q -- --inline; then
  sudo mv /usr/bin/systemd-tmpfiles /usr/bin/systemd-tmpfiles.real
  printf '#!/bin/bash\nargs=() rules=() inline=0\nfor a in "$@"; do\n  if [[ $a == --inline ]]; then inline=1\n  elif (( inline )) && [[ $a != -* ]]; then rules+=("$a")\n  else args+=("$a"); fi\ndone\nif (( inline )); then f=$(mktemp --suffix=.conf); printf "%%s\\n" "${rules[@]}" >"$f"; args+=("$f"); fi\nexec /usr/bin/systemd-tmpfiles.real "${args[@]}"\n' | sudo tee /usr/bin/systemd-tmpfiles >/dev/null
  sudo chmod 755 /usr/bin/systemd-tmpfiles
fi
pw_tree=$(mktemp -d)
cp -a "$OMARCHY_PATH"/{bin,default,etc,migrations,test} "$pw_tree"/
expiry=$pw_tree/test/shell.d/nopasswd-sudo-expiry-test.sh
expect "S6 upstream's hook assertion found once" 1 "$(grep -c '^  rm "\$PACKAGE_HOOK"$' "$expiry")"
sed -i '/^  rm "\$PACKAGE_HOOK"$/{s//  mv "$BOOT_CLEANUP_FILE" "$BOOT_CLEANUP_FILE.off"/;n;s/$/; mv "$BOOT_CLEANUP_FILE.off" "$BOOT_CLEANUP_FILE"/}' "$expiry"
for suite in passwordless-grant-lifecycle-test.sh nopasswd-sudo-expiry-test.sh; do
  (umask 022 && bash "$pw_tree/test/shell.d/$suite") >"/tmp/s6-$suite.log" 2>&1; st=$?
  expect "S6 upstream's $suite passes on the series' helper" "0:0" "$st:$(grep -c '^not ok' "/tmp/s6-$suite.log")"
  [[ $st == 0 ]] || onfail "/tmp/s6-$suite.log"
done
rm -rf "$pw_tree"
expect "S6 the inhibitor runs under Arch's umask" 0022 "$(sort -u "$HOME/stay-awake.umask" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect "S6 the inhibitor's leftover state no longer group-writable" "" "$(find "${inhibitor_state%/*}" -maxdepth 0 -perm /022 2>/dev/null; find "$inhibitor_state" -perm /022 2>/dev/null)"
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/omarchy-update-stay-awake"
rm -f "$HOME/shims/mise"
# 4.5's omarchy-update and omarchy-channel-set open with a sudo preamble that
# narrows PATH; the port's hand-off must come before it.
omarchy-update -y >/tmp/s6u.log 2>&1; st=$?
expect "S6 upstream omarchy-update hands over on rc" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s6u.log
grep -q "already at $RC_BASE" /tmp/s6u.log && ok "S6 handed-over update sees the rc target" || ko "S6 handed-over update sees the rc target"
omarchy-channel-set stable >/tmp/s6b.log 2>&1; st=$?
expect "S6 upstream omarchy-channel-set hands over" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s6b.log
expect "S6 back on stable" "${NEXT#v}" "$(omarchy-version)"
# What 4.5 brought and $NEXT does not ship goes with the switch, as the older package would take it.
check "S6 back on stable: 4.5's mise declarations gone" test ! -e /etc/mise/conf.d/omarchy-tools.toml
check "S6 back on stable: locale helper and its rule gone" sudo sh -c 'test ! -e /usr/bin/omarchy-locale-generate && test ! -e /etc/sudoers.d/omarchy-locale-generate'
check "S6 back on stable: passwordless sudo's packaged copies gone" sh -c 'test ! -e /usr/bin/omarchy-sudo-passwordless && test ! -e /usr/bin/omarchy-security-functions && test ! -e /usr/bin/omarchy-shell'
check "S6 back on stable: 4.0.x files stay" test -f /etc/sysctl.d/99-omarchy-sysctl.conf
expect "S6 back on stable: the admin's file at a 4.5 path is kept" "# the admin's" "$(cat /etc/mpv/mpv.conf)"

echo "== S7 the port updates itself"
git clone -q /tmp/port.git /tmp/port-dev
sed -i "s/OMARCHY_TAG_STABLE:-v[0-9.]*/OMARCHY_TAG_STABLE:-$BASE/" /tmp/port-dev/versions.env
git -C /tmp/port-dev commit -qam "pin $BASE upstream of the machine"
git -C /tmp/port-dev push -q origin HEAD:main
out=$(omarchy-update-available); st=$?
expect "S7 update-available sees the port behind" 0 "$st"
grep -q "omarchy-ubuntu 1 new commit" <<<"$out" && ok "S7 reports the port commit" || ko "S7 reports the port commit ($out)"
grep -q "omarchy ${NEXT#v} -> ${BASE#v}" <<<"$out" && ok "S7 reports the pin the remote carries" || ko "S7 reports the pin the remote carries ($out)"
# A change to a tracked file holds the port back, and the update says so twice.
echo "# mine" >>"$PORT/README.md"
omarchy-update-ubuntu -y >/tmp/s7a.log 2>&1; st=$?
expect "S7 updater exit with the port held" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s7a.log
grep -qE '^ +M README\.md' /tmp/s7a.log && ok "S7 a tracked change holds the port, listed" || { ko "S7 a tracked change holds the port, listed"; onfail /tmp/s7a.log; }
grep -q "The port itself was not updated: it has local changes" /tmp/s7a.log && ok "S7 says it again at the end" || ko "S7 says it again at the end"
expect "S7 port still behind" 1 "$(git -C "$PORT" rev-list --count HEAD..origin/main)"
git -C "$PORT" checkout -q -- README.md
# An untracked file, as an older port's dropped example leaves behind, does not.
touch "$PORT/config/hypr/monitors.lua.example"
omarchy-update-ubuntu -y >/tmp/s7.log 2>&1; st=$?
expect "S7 updater exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s7.log
grep -q "restarting on the new copy" /tmp/s7.log && ok "S7 re-executed on the pulled copy" || ko "S7 re-executed on the pulled copy"
expect "S7 pin from the pulled port applied" "$BASE" "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)"
rm -f "$PORT/config/hypr/monitors.lua.example"

echo "== S16 sudo asks once on a terminal"
# A password for tester, and an inhibitor that needs root without refreshing
# sudo's timestamp and drops it outside an update's session, as 4.5's does.
echo tester:harness | sudo chpasswd
echo 'tester ALL=(ALL) ALL' | sudo tee /etc/sudoers.d/tester >/dev/null
sudo -k
printf '#!/bin/bash\n[[ $1 != start ]] || /usr/bin/sudo -N /usr/bin/true\n[[ ${OMARCHY_UPDATE_SUDO_SESSION:-} == 1 ]] || /usr/bin/sudo -k\n' >"$HOME/shims/omarchy-update-stay-awake"
# A missing helper sends the update through a root step after the inhibitor's.
echo harness | sudo -S rm -f /usr/bin/omarchy-theme-set-browser-policy 2>/dev/null
sudo -k
# A terminal that answers each prompt as it comes: typed-ahead input would be
# eaten by gum, which reads the terminal for its colours.
cat >/tmp/answer-sudo.py <<'EOF'
import os, pty, select, signal, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
prompts, tail, deadline = 0, b"", time.time() + 300
with open("/tmp/s16.typescript", "wb") as log:
    while time.time() < deadline:
        if not select.select([fd], [], [], 1)[0]:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        log.write(data)
        tail = (tail + data)[-200:]
        if b"password for tester" in tail:
            prompts, tail = prompts + 1, b""
            time.sleep(0.2)
            os.write(fd, b"harness\n")
    else:
        os.kill(pid, signal.SIGKILL)
os.close(fd)
print(prompts)
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
EOF
prompts=$(python3 /tmp/answer-sudo.py omarchy-update-ubuntu -y 2>/dev/null); st=$?
expect "S16 updater exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s16.typescript
expect "S16 one password prompt" 1 "$prompts"
check "S16 the root step ran on that authorization" test -x /usr/bin/omarchy-theme-set-browser-policy
echo harness | sudo -S sh -c "echo 'tester ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/tester" 2>/dev/null
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/omarchy-update-stay-awake"

echo "== S17 a pinned app's clone moves to its next tag"
# The build steps compare describe with the pin; a tag that only reached
# FETCH_HEAD rebuilt the app on every update.
git init -q -b main /tmp/app-src
git -C /tmp/app-src commit -q --allow-empty -m one && git -C /tmp/app-src tag v1
git -C /tmp/app-src commit -q --allow-empty -m two && git -C /tmp/app-src tag -a v2 -m v2
(REPO_DIR=$PORT && source "$PORT/lib/common.sh" && git_checkout /tmp/app file:///tmp/app-src v1 && git_checkout /tmp/app file:///tmp/app-src v2) >/tmp/s17.log 2>&1
expect "S17 the clone names the new tag" v2 "$(git -C /tmp/app describe --tags 2>/dev/null)"

echo "== S18 Hyprland's config checked by the running compositor"
# 0.56's verify segfaults on 4.5's Lua config whatever it holds; the
# compositor that reloaded it reports the errors.
printf '#!/bin/bash\n[[ $1 != configerrors ]] || echo "hyprland.lua:3: a bad thing"\n' >"$HOME/shims/hyprctl"
printf '#!/bin/bash\nexit 139\n' >"$HOME/shims/Hyprland"
omarchy-update-ubuntu -y >/tmp/s18.log 2>&1; st=$?
expect "S18 updater exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s18.log
grep -q "hyprland.lua:3: a bad thing" /tmp/s18.log && ok "S18 the compositor's config errors reported" || { ko "S18 the compositor's config errors reported"; onfail /tmp/s18.log; }
grep -q "verify-config failed" /tmp/s18.log && ko "S18 no verdict from a crashed verify" || ok "S18 no verdict from a crashed verify"
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/hyprctl"
printf '#!/bin/bash\nexit 0\n' >"$HOME/shims/Hyprland"

echo "== S8 dev channel"
omarchy-channel-ubuntu set dev >/tmp/s8.log 2>&1; st=$?
expect "S8 set dev exit" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s8.log
grep -q "left as it is" /tmp/s8.log && ok "S8 branch left alone" || ko "S8 branch left alone"
expect "S8 version" "dev ($(git -C "$OMARCHY_PATH" rev-parse --short HEAD))" "$(omarchy-version)"
omarchy-channel-ubuntu set stable >/dev/null 2>&1

echo "== S11 an unknown ref"
omarchy-update-ubuntu v9.9.9 >/tmp/s11.log 2>&1; st=$?
expect "S11 refused" 2 "$st"
expect "S11 branch intact" ubuntu "$(git -C "$OMARCHY_PATH" branch --show-current)"

echo "== S12 a rebuild cut short"
mkdir -p "$OMARCHY_PATH/.git/rebase-apply"
omarchy-update-ubuntu -y >/tmp/s12.log 2>&1; st=$?
expect "S12 refused" 1 "$st"
grep -q "was interrupted" /tmp/s12.log && ok "S12 says why" || ko "S12 says why"
rmdir "$OMARCHY_PATH/.git/rebase-apply"

echo "== S13 a patch dropped from the series"
git -C "$PORT" rm -q patches/stable/0012-*.patch && git -C "$PORT" commit -qm "series: drop 0012" && git -C "$PORT" push -q origin HEAD:main
omarchy-update-ubuntu -y >/tmp/s13.log 2>&1; st=$?
expect "S13 updater rebuilds" 0 "$st"
[[ $st == 0 ]] || onfail /tmp/s13.log
expect "S13 patches on top" 12 "$(git -C "$OMARCHY_PATH" rev-list --count "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)..ubuntu")"
git -C "$PORT" revert --no-edit HEAD >/dev/null && git -C "$PORT" push -q origin HEAD:main
expect "S13 series back to 13 files" 13 "$(ls "$PORT"/patches/stable/*.patch | wc -l)"
omarchy-update-ubuntu -y >/tmp/s13b.log 2>&1 || onfail /tmp/s13b.log
expect "S13 series restored" 13 "$(git -C "$OMARCHY_PATH" rev-list --count "$(git -C "$OMARCHY_PATH" describe --tags --abbrev=0)..ubuntu")"

echo "== S9 upstream-check inside the container"
out=$(cd /tmp && omarchy-upstream-check --channel stable --target "$NEXT" 2>&1); st=$?
# Exit 1 is a report with something to read (a pin behind upstream, say); 2 is the check failing.
(( st <= 1 )) && ok "S9 stable check ran (exit $st)" || { ko "S9 stable check ran (exit $st)"; sed -n 1,40p <<<"$out" | sed 's/^/      /'; }
grep -q "13 patches rebase cleanly" <<<"$out" && ok "S9 stable: series rebases" || { ko "S9 stable: series rebases"; sed -n 1,14p <<<"$out" | sed 's/^/      /'; }
if grep -q '^## Versions' <<<"$out"; then
  grep -q "pins match" <<<"$out" && ok "S9 versions compared against the ring and the mirror" || { ko "S9 versions compared"; grep -A12 '^## Versions' <<<"$out" | sed 's/^/      /'; }
fi
grep -q "stable channel" <<<"$out" && ok "S9 header names the channel" || ko "S9 header names the channel"
out=$(cd /tmp && omarchy-upstream-check --channel rc --target "$RC_BASE" 2>&1); st=$?
(( st <= 1 )) && ok "S9 rc check ran (exit $st)" || { ko "S9 rc check ran (exit $st)"; sed -n 1,40p <<<"$out" | sed 's/^/      /'; }
grep -q "$RC_PATCHES patches rebase cleanly" <<<"$out" && ok "S9 rc: series rebases" || { ko "S9 rc: series rebases"; sed -n 1,14p <<<"$out" | sed 's/^/      /'; }
grep -q "rc channel" <<<"$out" && ok "S9 rc header names the channel" || ko "S9 rc header names the channel"

echo "== S14 a re-run of the bootstrap asking for another channel"
(cd "$PORT" && OMARCHY_CHANNEL=rc REPO_DIR=$PORT ./bootstrap.sh 30) >/tmp/s14.log 2>&1; st=$?
expect "S14 refused" 1 "$st"
grep -q "switch with: omarchy-channel-set rc" /tmp/s14.log && ok "S14 points at omarchy-channel-set" || { ko "S14 points at omarchy-channel-set"; tail -3 /tmp/s14.log; }
expect "S14 channel untouched" stable "$(cat "$HOME/.local/state/omarchy/channel")"

echo "== S21 the screen recorder's KMS server goes to root, with its capability"
cp /usr/bin/true "$HOME/.local/bin/gsr-kms-server"
omarchy-update-ubuntu -y >/tmp/s21.log 2>&1 || onfail /tmp/s21.log
expect "S21 root's, in /usr/local/bin" "root 755" "$(stat -c '%U %a' /usr/local/bin/gsr-kms-server 2>/dev/null)"
expect "S21 with cap_sys_admin" "cap_sys_admin=ep" "$(getcap /usr/local/bin/gsr-kms-server 2>/dev/null | awk '{print $NF}')"
check "S21 none left in ~/.local/bin" test ! -e "$HOME/.local/bin/gsr-kms-server"

echo "== S19 removed preinstalls stay out of the steps"
common() { (cd "$PORT" && REPO_DIR=$PORT bash -c "source lib/common.sh; $1") 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
expect "S19 nothing removed without the marker" "" "$(common removed_preinstalls)"
apps_before=$(common base_apps)
mkdir -p "$HOME/.local/state/omarchy" && touch "$HOME/.local/state/omarchy/preinstalls-removed"
removed=$(common removed_preinstalls)
[[ " $removed " == *" cliamp "* && " $removed " == *" omacalc "* ]] && ok "S19 the marker names what upstream's removal drops" || ko "S19 the marker names what upstream's removal drops ($removed)"
apps_after=$(common base_apps)
[[ " $apps_before " == *" omacalc "* && " $apps_after " != *" omacalc "* ]] && ok "S19 a removed companion app is not rebuilt" || ko "S19 a removed companion app is not rebuilt ($apps_before -> $apps_after)"
rm -f "$HOME/.local/state/omarchy/preinstalls-removed"

echo "== S10 edge bootstrap (the rc series on upstream's head; it may conflict as upstream moves)"
# The channel file is in the home getent names, whatever HOME says, and the
# bootstrap refuses a channel other than the recorded one: set aside, as a
# machine bootstrapped on edge would have none.
mv "$HOME/.local/state/omarchy/channel" /tmp/channel.saved
export HOME=/tmp/edgehome; mkdir -p "$HOME"; export OMARCHY_PATH=$HOME/.local/share/omarchy
(cd "$PORT" && OMARCHY_CHANNEL=edge REPO_DIR=$PORT ./bootstrap.sh 30) >/tmp/s10.log 2>&1; st=$?
if [[ $st == 0 ]]; then
  ok "S10 edge bootstrap applied the rc series on $(git -C "$OMARCHY_PATH" describe --tags)"
  # Edge's base is upstream's head, past the last tag.
  expect "S10 edge patches on top" "$RC_PATCHES" "$(git -C "$OMARCHY_PATH" rev-list --count origin/HEAD..ubuntu)"
elif conflict=$(grep -m1 -E 'does not rebase|does not apply' /tmp/s10.log); then
  echo "      edge bootstrap exit $st: $conflict"
  expect "S10 failed step leaves no branch behind" "" "$(git -C "$OMARCHY_PATH" branch --list ubuntu)"
  check "S10 failed step leaves no rebase in progress" test ! -d "$OMARCHY_PATH/.git/rebase-merge" -a ! -d "$OMARCHY_PATH/.git/rebase-apply"
else
  ko "S10 edge bootstrap failed, and not on a patch (exit $st)"
  onfail /tmp/s10.log
fi
export HOME=/home/tester; export OMARCHY_PATH=$HOME/.local/share/omarchy
mv /tmp/channel.saved "$HOME/.local/state/omarchy/channel"

echo
echo "passed $pass, failed $fail"
(( fail == 0 ))
