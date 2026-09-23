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
- The menu's Install/Remove entries work against dpkg, snap and flatpak.

## What stays Ubuntu

GDM instead of SDDM (Omarchy's SDDM theme needs a newer SDDM), Ubuntu's Plymouth,
apt instead of pacman (the Omarchy "Install" menu maps Arch names to apt when it
can and tells you when it cannot), and no AUR. See [docs/deviations.md](docs/deviations.md).

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

Personal files are never overwritten: existing `~/.config/hypr/*.lua`,
terminal configs and `~/.bashrc` are backed up with a `.bak-omarchy` suffix the
first time and left alone afterwards. `monitors.lua` is yours to edit.

## Layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | runs `install/*.sh` in order; `-root.sh` steps run as root |
| `install/` | numbered steps: apt, extra .debs, Qt, toolchains, Omarchy checkout, Quickshell, tools, user, root, config, session, browser policy, PATH |
| `versions.env` | pinned versions for everything cloned or downloaded |
| `patches/` | the `ubuntu` branch of the Omarchy fork as `git am` patches (dpkg guards, apt helpers, update hand-off, logout without uwsm) |
| `config/hypr/` | `hyprland.lua` and `autostart.lua` with the Ubuntu/GDM glue; `monitors.lua.example` |
| `etc/` | PAM stacks (lock, polkit with fingerprint), polkit rule, wayland session entry |
| `bin/` | `omarchy-update-ubuntu`, `omarchy-build-qt-apps`, `omarchy-keyring-passwordless` |
| `docs/` | deviations from upstream and the gotchas found while porting |

## Updating

`omarchy-update-ubuntu` fetches the newest upstream tag, rebases the `ubuntu`
branch on it, runs the new migrations (Arch-only ones become a question),
reapplies the root-side pieces if upstream changed them and restarts the shell.
Bump `versions.env` and rerun the matching `bootstrap.sh` step when Omarchy
raises its Quickshell or app requirements.

## Status

Built and used daily on a Dell Pro 14 Plus (Lunar Lake) with Ubuntu 24.04.5,
Hyprland 0.56 from `ppa:cppiber/hyprland`, Omarchy v4.0.4. Screen sharing,
screen recording, fingerprint lock and polkit, Taildrop, dictation and the
whole theme pipeline work. Not covered: Omarchy's ISO installer, Limine and
snapper snapshots, the SDDM theme, Plymouth.
