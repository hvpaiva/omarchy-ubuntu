# Deviations from upstream Omarchy

Everything not listed here is upstream's own code and configuration, unchanged.

| Area | Upstream (Arch) | Here (Ubuntu 24.04) | Why |
|---|---|---|---|
| Display manager | SDDM with Omarchy's Qt6 theme | GDM, `omarchy.desktop` wayland session (uwsm); packaged `Hyprland` entry as fallback | Omarchy's theme needs SDDM 0.21; noble ships 0.20 |
| Boot splash | Plymouth theme installed through mkinitcpio hooks | Ubuntu's Plymouth | mkinitcpio does not exist on Ubuntu |
| Packages | pacman, AUR, `omarchy-pkg-*` | apt, official .debs from GitHub releases, source builds; `omarchy-pkg-installed` maps Arch names to dpkg/snap/flatpak/command | no pacman |
| Update | `omarchy-update` (pacman, snapper, keyring) | `omarchy-update-ubuntu`: git tag rebase, reviewed migrations | migrations and updates assume pacman |
| Qt / Quickshell | distro packages | Qt 6.11 from aqtinstall in `~/.local/opt/Qt`, Quickshell built with a compat header for `wl_fixes` | noble has Qt 6.4 and libwayland 1.22 |
| ImageMagick | `magick` (IM7) | `/usr/local/bin/magick` shim to `convert` | noble ships IM6 |
| Session env | `/usr/share/uwsm/env.d/10-omarchy` | block in `~/.config/uwsm/env` and at the top of `~/.bashrc`; Lua glue in `hyprland.lua` for the direct GDM entry | the PPA's uwsm 0.26 ignores `env.d`; the direct entry has no login shell |
| User units | started by `graphical-session.target` | same under uwsm; `autostart.lua` also starts them for the direct entry | `graphical-session.target` refuses manual start |
| Lock PAM | `system-local-login` + `pam_faillock` | `pam_unix`/`pam_sss` stack, `common-account`; fingerprint in its own stack | no faillock on Ubuntu |
| Polkit PAM | `/etc/pam.d/polkit-1` written by the fingerprint setup | same file, Ubuntu modules | Ubuntu has no `polkit-1` PAM file; the dialog needs it to show fingerprint mode |
| Polkit identities | wheel = the user | rule returning the requesting sudo user | Ubuntu offers the whole sudo group; the agent picked the first member |
| Browser policy | helper in `/usr/bin`, `%wheel` sudoers | copy of the helper in `/usr/bin`, `%sudo`; Firefox skipped (snap) | packaged path is hard-coded upstream |
| Input method | fcitx5 from pacman | fcitx5 from apt; Ubuntu's IBus autostart hidden | uwsm honours XDG autostart |
| Screen recorder capability | package `.install` sets it | `setcap` in the root step on `~/.local/bin/gsr-kms-server` | user-local install |
| Fonts | `ttf-jetbrains-mono-nerd`, `ttf-cascadia-mono-nerd` | Nerd Fonts release archives into `~/.local/share/fonts` | not packaged |
| Bash | skel bashrc sources Omarchy's `default/bash/rc` | only the env-bootstrap block is added; your shell config stays | personal choice; `default/bash/completions` is worth sourcing |
