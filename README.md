# omarchy-ubuntu

Omarchy 4 on Ubuntu 24.04: the same shell, menus, themes, lock screen, companion
apps and keybindings as [Omarchy](https://omarchy.org), on a machine whose
operating system you are not allowed to replace.

> **Installed before 2026-10-22?** This repository's history was rewritten
> that day, so your copy cannot fast-forward and the updater leaves it behind.
> [Updating](#updating) has the commands to bring it to main once.

## Who this is for

If you can choose your operating system, install Omarchy. It is a complete,
opinionated Arch Linux setup and this project will never be as clean as the
real thing.

This project exists for the other case: a work laptop that has to stay on
Ubuntu (company policy, managed fleet, corporate VPN or agents that only
support Ubuntu), where you still want Omarchy's desktop experience. It keeps
Ubuntu, GDM and apt, and layers Omarchy on top the way Omarchy's own developers
run it: a git checkout in "dev link" mode, with the shell built from source.

## What you get

- `omarchy-shell` (Omarchy's Quickshell build against Qt 6.12): bar, menu, notifications,
  OSD, audio/bluetooth/network/power/monitor panels, wallpaper, lock screen with
  password and fingerprint, idle screensaver, clipboard and emoji pickers,
  polkit dialog.
- Omarchy's Hyprland Lua configuration, themes (with terminal, GTK, btop and
  browser policy re-theming), keybindings and menus.
- The companion apps: tensaku (screenshots), ttfx (screensaver), omacalc,
  omawrite, omacut, cliamp, herdr, aether, hyprland-preview-share-picker,
  gpu-screen-recorder, voxtype (dictation), LocalSend.
- Updates: `omarchy-update-ubuntu` (also behind the menu's Update entry) rebuilds
  the port's patches on the tag its channel pins and runs the new migrations;
  Update > Channel switches between stable, rc, edge and dev as upstream does.
- The menu's Install/Remove entries work against dpkg, snap and flatpak, and
  install what apt lacks from the vendor's own apt repository or .deb, from
  Omarchy's package repository, from mise, or from the upstream release.

## What stays Ubuntu

GDM instead of SDDM (Omarchy's SDDM theme needs a newer SDDM), Ubuntu's Plymouth,
apt instead of pacman (the Omarchy "Install" menu maps Arch names to apt or to
the vendor's own channel), and no AUR. See [docs/deviations.md](docs/deviations.md).

## Install

```
sudo apt install git
git clone https://github.com/<you>/omarchy-ubuntu ~/.local/share/omarchy-ubuntu
~/.local/share/omarchy-ubuntu/bootstrap.sh
```

The bootstrap is idempotent and resumable (`bootstrap.sh --list`, `bootstrap.sh 40 45`).
It asks for your password for the root steps (through polkit when a session is
up, otherwise sudo). Expect 20 to 40 minutes: it downloads Qt (about 1 GB) and
compiles Quickshell and the companion apps. When it finishes, log out and pick
`Omarchy (Hyprland uwsm)` in GDM once; autologin then targets it. Autologin
cannot unlock Ubuntu's `login` keyring, which is encrypted with your password;
run `bin/omarchy-keyring-passwordless` once from a terminal to get Omarchy's
passwordless default keyring (see [docs/gotchas.md](docs/gotchas.md)).

`OMARCHY_CHANNEL=rc` in front of the bootstrap follows upstream's release
candidates instead of its releases; see [Channels](#channels).

Personal files are never overwritten: existing `~/.config/hypr/*.lua` and
`~/.bashrc` are backed up with a `.bak-omarchy` suffix the first time and left
alone afterwards; a terminal config that already exists is kept as it is.
`monitors.lua` is yours to edit.

Personal configuration is not this project's business: it lives in
[hvpaiva/dotfiles](https://github.com/hvpaiva/dotfiles), whose bootstrap runs this one first
on Ubuntu and then layers the personal files on top. `docs/deviations.md` lists which files
this port itself writes into `$HOME`, so that layer knows what not to track.

## Layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | runs `install/*.sh` in order; `-root.sh` steps run as root |
| `install/` | numbered steps: apt, extra .debs, Qt, toolchains, Omarchy checkout, Quickshell, tools, user, root, config, session, browser policy, PATH |
| `lib/` | `channel.sh` (channels, their pins and series), `migrations.sh` (what the updater does with migrations that reach for Arch), `units.sh` (user units), `catalog.py` (every package name an Omarchy tree can hand its package helpers), `common.sh` |
| `migrations/` | the port's own migrations, run by the updater before upstream's for what its package upgrade would have done to the machine (`.applied/migrations/` records them; a `-root.sh` beside one is its root half) |
| `versions.env` | pinned versions for everything cloned or downloaded, the Omarchy tag of each channel among them; `versions.rc.env` holds what the rc channel pins differently |
| `patches/stable/` | the `ubuntu` branch of the Omarchy fork as `git am` patches (apt backend behind the package helpers, update and channel hand-offs, logout without uwsm, theme and app fixes), with the tag the series was cut on in `base`; each one touches as little of upstream as it can, so the next tag rebases without conflicts. A channel whose series differs gets its own directory (`patches/rc/`). `bin/omarchy-port-series` cuts a series from a fork branch. `patches/apps/` holds what `omarchy-build-app` applies to a companion app's source when noble's libraries are behind what it was written against |
| `config/hypr/` | `hyprland.lua` and `autostart.lua` with the Ubuntu/GDM glue; the other Hyprland files are seeded from upstream's stubs |
| `etc/` | PAM stacks (lock, polkit with fingerprint), polkit rule, wayland session entry |
| `bin/` | `omarchy-update-ubuntu`, `omarchy-channel-ubuntu`, `omarchy-upstream-check`, `omarchy-port-series`, `omarchy-build-app` (companion apps from source), `omarchy-keyring-passwordless` |
| `.github/workflows/upstream.yml` | weekly report of what the next Omarchy brings for each channel of the port, posted as issues |
| `.github/workflows/test.yml` | the harness's scenarios on every pull request and push to main; the full bootstrap, per channel, when dispatched with its switch |
| `test/harness/` | the container harness: `run.sh` (the updater and channel scenarios of `test.sh`) and `full.sh` (the bootstrap, steps 10 to 45, of `full-test.sh`, then a check that every package name the checkout can ask for resolves), both on a clean Ubuntu 24.04 image |
| `docs/` | deviations from upstream and the gotchas found while porting |

## Testing

Both halves of the harness need Docker and run the port at a ref of a repository, this checkout included:

```sh
test/harness/run.sh "$PWD"                                   # scenarios: channels, the updater's branch rebuild, migrations, switches, self-update
test/harness/full.sh "$PWD" HEAD 10 12 15 20 25 30 40 45     # a fresh bootstrap as far as a container goes; OMARCHY_CHANNEL=rc for the rc channel
```

The bootstrap keeps apt's package cache and index lists in Docker volumes between runs (`CACHE=<name>` for a second pair, `APT_CACHE_DIR=<dir>` for bind-mounted directories), and every step's full output under `test/harness/logs/`. Steps 50 to 80 need a session and a real kernel: they only run on a machine.

## Updating

`omarchy-update-ubuntu` fast-forwards this repo, rebuilds the `ubuntu` branch
from the series under `patches/` (applied on the tag it was cut on, then
rebased onto the tag the channel pins), then brings the machine up to it the
way upstream's update brings every package to the ring's version before the
migrations run: the pinned tools (the `.deb` tools as root when one is behind,
Qt, Quickshell, the companion apps and the fonts as the user;
`OMARCHY_UPDATE_TOOLS=0` leaves them to you), the root-side pieces if upstream
changed them (helpers in `/usr/bin`, sudoers, system tweaks, fcitx5's glyphs)
and every user unit upstream ships (minus `lib/units.sh`'s skip list). Then the
port's own migrations (`migrations/`), upstream's new ones (`lib/migrations.sh`
names the Arch-only ones it marks done instead), the post-update hooks, and the
shell restarts. `-y` asks nothing, as upstream's `omarchy-update -y`.

**From a port cloned before 2026-10-22**, this repository cannot
fast-forward: its history was rewritten that day, and `omarchy-update-ubuntu`
ends saying the port itself was not updated. Bring it to main once, then
update. The reset drops a change of yours to a tracked file in this
repository, so stash or copy one first. A port older than 2026-10-21 (before
the channels: that updater took the newest tag of the checkout, rebased the
branch onto it and never updated the port itself) may also have stopped in a
rebase conflict on `v4.5.0-rc1`; abort that first. The branch is rebuilt from
the series on the stable tag, nothing of the old one is needed
([#18](https://github.com/hvpaiva/omarchy-ubuntu/issues/18)):

```sh
git -C ~/.local/share/omarchy rebase --abort        # only if a rebase is in progress
git -C ~/.local/share/omarchy-ubuntu fetch origin
git -C ~/.local/share/omarchy-ubuntu reset --hard origin/main
omarchy-update-ubuntu
```

From then on the updater updates itself first, and stops with the same
instructions if it finds a rebase that an earlier updater left in progress.

### Channels

Upstream's `omarchy-channel-set` picks a package ring; here it records the
channel in `~/.local/state/omarchy/channel` and updates onto it (the menu's
Update > Channel entries do the same):

| Channel | What the `ubuntu` branch is rebuilt on |
|---|---|
| `stable` | the release tag pinned as `OMARCHY_TAG_STABLE` in `versions.env` |
| `rc` | the tag pinned as `OMARCHY_TAG_RC`: a pre-release, or the release while no newer pre-release is out, as upstream's rc ring carries |
| `edge` | upstream's default branch, unpinned |
| `dev` | nothing: the checkout is yours and the updater leaves its branch alone |

A tag reaches a pin once the port was checked against it (below), the way a
release only reaches upstream's ring once omarchy-pkgs built it; a machine
then sees the new pin as an update the next time the bar asks
(`omarchy-update-available`). `omarchy-version` reports the tag the checkout
sits on, spelled as upstream's package (`4.0.6`, `4.5.0rc1`).

## Following upstream

Omarchy tags a release every week or two and lands dozens of commits a day
in between. Rebuilding the `ubuntu` branch covers the checkout; what the port reproduces by
hand outside it (package lists, `etc/`, install steps, user units) would
drift in silence. `omarchy-upstream-check` reads what the next tag brings
before anything is touched:

```
omarchy-upstream-check                    # this machine's channel: its base -> the newest ref the channel admits
omarchy-upstream-check --channel rc       # another channel: its pin -> its newest
omarchy-upstream-check --branch           # base -> upstream's default branch, what edge follows
omarchy-upstream-check --base v4.0.3 --target v4.0.4
```

It works on a throwaway clone and reports, in Markdown: whether the port's
patches rebase cleanly (and on which files they conflict), each package added
or removed upstream with the Ubuntu source the port knows for it, each package
name a menu entry or a command asks for that it did not before, the new
migrations and whether they use Arch tooling, every change in the directories
the port mirrors by hand, the `etc/` files step 57 neither installs nor lists
as skipped, the new user units, and every version `versions.env` pins against
what the channel's ring (`pkgs.omarchy.org`) and upstream's Arch snapshot
mirror carry at the target. It exits 1 on a conflict, on a package without an
Ubuntu source or on a pin behind upstream, 0 otherwise.

The `upstream` workflow runs it every Monday (and on demand, for one channel
or all, with a ref of your choice) and keeps one issue per channel: for stable
and rc, the newest ref the channel admits while its pin is behind it, closed
once the pin catches up or a newer ref supersedes it; for edge, a rolling
preview of upstream's default branch over the rc pin. `omarchy-update-ubuntu`
prints the command for the tag it is about to apply.

## Status

Built and used daily on a Dell Pro 14 Plus (Lunar Lake) with Ubuntu 24.04.5,
Hyprland 0.56 from `ppa:cppiber/hyprland`, Omarchy v4.0.6. Screen sharing,
screen recording, fingerprint lock and polkit, Taildrop, dictation and the
whole theme pipeline work. Not covered: Omarchy's ISO installer, Limine and
snapper snapshots, the SDDM theme, Plymouth.
