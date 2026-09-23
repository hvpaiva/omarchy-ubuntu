# Deviations from upstream Omarchy

Everything not listed here is upstream's own code and configuration, unchanged.

| Area | Upstream (Arch) | Here (Ubuntu 24.04) | Why |
|---|---|---|---|
| Display manager | SDDM with Omarchy's Qt6 theme | GDM, `omarchy.desktop` wayland session (uwsm); packaged `Hyprland` entry as fallback | Omarchy's theme needs SDDM 0.21; noble ships 0.20 |
| Boot splash | Plymouth theme installed through mkinitcpio hooks | Ubuntu's Plymouth | mkinitcpio does not exist on Ubuntu |
| Packages | pacman, AUR, `omarchy-pkg-*` | apt, official .debs from GitHub releases, mise for what its registry carries (herdr, cliamp, the agent CLIs), source builds for the rest; `omarchy-pkg-installed` maps Arch names to dpkg/snap/flatpak/command | no pacman; mise first is the user's rule |
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
| Chromium | Arch's `chromium`; launcher reads `~/.config/chromium-flags.conf`; Omarchy's initial preferences | Debian's `chromium` from the xtradeb PPA, pinned so nothing else comes from it; `/etc/chromium.d/omarchy-user-flags` reads the flags file; Debian's first-run preferences diverted, Omarchy's in place; AppArmor profile granting `userns` | Ubuntu ships Chromium only as a snap, whose desktop file name, confinement and policy path break Omarchy's launchers, extensions and theme policy |
| System tweaks | `etc/` tree installed by the package | `57-system-tweaks-root.sh` copies the same files (`%wheel` to `%sudo`, `omarchy-dns` copied to `/usr/bin`); `58-system-extras-root.sh` adds the pieces that need a package or an edit on Ubuntu (docker DNS, cups-browsed, zram, sleep hooks, oomd for app.slice) | same files, different install path |
| logind inhibit delay | `20-inhibit-delay.conf` (15 s) | same content as `zz-omarchy-inhibit-delay.conf` | Ubuntu's unattended-upgrades ships a 30 s drop-in that sorts after `20-` |
| USB autosuspend | `modprobe.d` option | same file plus a tmpfiles `w` on `/sys/module/usbcore/parameters/autosuspend` | usbcore is built into Ubuntu's kernel, so modprobe options never apply |
| zram | `zram-generator.conf.d/90-omarchy.conf` under `/usr/lib` | same content in `/etc/systemd/zram-generator.conf` | noble's zram-generator 1.1.2 reads no `conf.d`; the disk swapfile stays at priority -1 for hibernation |
| cups-browsed | `cups-files.conf` with Arch's uid/gid 209, `SystemGroup cups-browsed sys root` | Ubuntu's `cups-files.conf` with `cups-browsed` added to `SystemGroup`; queue settings appended to Ubuntu's `cups-browsed.conf` | Arch ids and Ubuntu's `BrowseRemoteProtocols dnssd` |
| Docker | `daemon.json` from the package | `dns` and `bip` merged into the existing `daemon.json`, docker restarted only at reboot | local log settings kept; a restart stops running containers |
| Not ported | mkinitcpio, limine, plymouth (the menu's Style > Unlock is hidden with `"style.unlock": {"when":"false"}` in `~/.config/omarchy/extensions/omarchy-menu.jsonc`), sddm, faillock, nsswitch, ufw-docker | left to Ubuntu | Arch boot stack, no faillock in Ubuntu's PAM, `nsswitch` carries `sss` for the corporate login |
| Global user units | Arch enables none | `foot-server`, `fumon` and `hyprsunset` globally disabled | Ubuntu's presets enable them for every session; Omarchy starts hyprsunset from the nightlight toggle only |
