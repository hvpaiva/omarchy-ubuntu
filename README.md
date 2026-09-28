# omarchy-ubuntu

Omarchy 4 on Ubuntu 24.04: the same shell, menus, themes, lock screen, companion
apps and keybindings as [Omarchy](https://omarchy.org), on a machine whose
operating system you are not allowed to replace.

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

- `omarchy-shell` (Quickshell 0.3.1 against Qt 6.11): bar, menu, notifications,
  OSD, audio/bluetooth/network/power/monitor panels, wallpaper, lock screen with
  password and fingerprint, idle screensaver, clipboard and emoji pickers,
  polkit dialog.
- Omarchy's Hyprland Lua configuration, themes (with terminal, GTK, btop and
  browser policy re-theming), keybindings and menus.
- The companion apps: tensaku (screenshots), ttfx (screensaver), omacalc,
  omawrite, omacut, cliamp, herdr, aether, hyprland-preview-share-picker,
  gpu-screen-recorder, voxtype (dictation), LocalSend.
- Updates: `omarchy-update-ubuntu` (also behind the menu's Update entry) rebases
  the port's patches on the next upstream tag and reviews new migrations.
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
| `versions.env` | pinned versions for everything cloned or downloaded |
| `patches/` | the `ubuntu` branch of the Omarchy fork as `git am` patches (apt backend behind the package helpers, update hand-off, logout without uwsm, theme and app fixes); each one touches as little of upstream as it can, so the next tag rebases without conflicts |
| `config/hypr/` | `hyprland.lua` and `autostart.lua` with the Ubuntu/GDM glue; `monitors.lua.example` |
| `etc/` | PAM stacks (lock, polkit with fingerprint), polkit rule, wayland session entry |
| `bin/` | `omarchy-update-ubuntu`, `omarchy-upstream-check`, `omarchy-build-app` (companion apps from source), `omarchy-keyring-passwordless` |
| `.github/workflows/upstream.yml` | weekly report of what the next Omarchy brings for the port, posted as an issue |
| `docs/` | deviations from upstream and the gotchas found while porting |

## Updating

`omarchy-update-ubuntu` fetches the newest upstream tag, rebases the `ubuntu`
branch on it, runs the new migrations (Arch-only ones become a question),
reapplies the root-side pieces if upstream changed them, installs every user
unit upstream ships (minus `lib/units.sh`'s skip list) and restarts the shell.
Bump `versions.env` and rerun the matching `bootstrap.sh` step when Omarchy
raises its Quickshell or app requirements.

## Following upstream

Omarchy tags a release every week or two and lands dozens of commits a day
in between. The git rebase covers the checkout; what the port reproduces by
hand outside it (package lists, `etc/`, install steps, user units) would
drift in silence. `omarchy-upstream-check` reads what the next tag brings
before anything is touched:

```
omarchy-upstream-check                    # pinned tag -> newest release tag
omarchy-upstream-check --branch           # pinned tag -> upstream's default branch
omarchy-upstream-check --base v4.0.3 --target v4.0.4
```

It works on a throwaway clone and reports, in Markdown: whether the port's
patches rebase cleanly (and on which files they conflict), each package added
or removed upstream with the Ubuntu source the port knows for it, the new
migrations and whether they use Arch tooling, every change in the directories
the port mirrors by hand, the `etc/` files step 57 neither installs nor lists
as skipped, and the new user units. It exits 1 on a conflict or on a package
without an Ubuntu source, 0 otherwise.

The `upstream` workflow runs it every Monday (and on demand, with a ref of
your choice) and keeps the result in an issue: one per release tag the port
is not on yet, and a rolling preview of the default branch while the port is
on the newest tag. `omarchy-update-ubuntu` prints the command for the tag it
is about to apply.

## Status

Built and used daily on a Dell Pro 14 Plus (Lunar Lake) with Ubuntu 24.04.5,
Hyprland 0.56 from `ppa:cppiber/hyprland`, Omarchy v4.0.4. Screen sharing,
screen recording, fingerprint lock and polkit, Taildrop, dictation and the
whole theme pipeline work. Not covered: Omarchy's ISO installer, Limine and
snapper snapshots, the SDDM theme, Plymouth.
