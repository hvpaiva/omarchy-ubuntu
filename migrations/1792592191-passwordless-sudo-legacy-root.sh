#!/bin/bash
# The root half of 1792592191-passwordless-sudo-legacy.sh: what the 4.5
# helper's __migrate does under its lock. The pre-4.5 omarchy-sudo-passwordless
# wrote one `NOPASSWD: ALL` rule per user under a reserved prefix and armed a
# transient expiry timer for it. Anything else under that prefix is moved
# aside for the administrator, never left live, as upstream does.
source "${REPO_DIR:?}/lib/common.sh"
need_root

marker=/var/lib/omarchy/migrations/1788163635
[[ -f $marker ]] && exit 0
quarantine=/var/lib/omarchy/sudoers-quarantine

for rule in /etc/sudoers.d/99-omarchy-nopasswd-*; do
  [[ -e $rule || -L $rule ]] || continue
  suffix=${rule##*/99-omarchy-nopasswd-}
  if [[ -f $rule && ! -L $rule && $(<"$rule") == "$suffix ALL=(ALL) NOPASSWD: ALL" ]]; then
    rm -f -- "$rule"
    note "removed   $rule"
  else
    install -d -o root -g root -m 0755 /var/lib/omarchy
    install -d -o root -g root -m 0700 "$quarantine"
    target=$(mktemp -d "$quarantine/XXXXXXXXXX")
    printf '%s\n' "${rule##*/}" >"$target/name"
    mv -fT -- "$rule" "$target/policy"
    warn "$rule is not the old helper's rule; moved to $target/policy"
  fi
done

# The expiry timers were transient (systemd-run): stopping one is the end of it.
timers=$(systemctl list-units --all --plain --no-legend 'omarchy-nopasswd-expire-*.timer' 2>/dev/null | awk '{print $1}') || timers=""
for timer in $timers; do
  systemctl stop "$timer" >/dev/null 2>&1 || true
  note "stopped   $timer"
done

install -d -o root -g root -m 0755 /var/lib/omarchy /var/lib/omarchy/migrations
install -o root -g root -m 0644 /dev/null "$marker"
note "written   $marker"
