#!/bin/bash
# What Omarchy's omarchy-settings package does in /etc/skel and /usr/share,
# done in $HOME: the glyph font, the env-bootstrap hooks, state dirs, nerd fonts.
source "${REPO_DIR:?}/lib/common.sh"
need_user

bootstrap="$OMARCHY_PATH/default/bash/env-bootstrap"
[[ -r $bootstrap ]] || die "Omarchy checkout not found at $OMARCHY_PATH (run install/30-omarchy-checkout.sh)"

log "Omarchy glyph font"
install -Dm644 "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" "$OMARCHY_HOME/.local/share/fonts/omarchy/omarchy.ttf"
fc-cache -f "$OMARCHY_HOME/.local/share/fonts/omarchy" >/dev/null

log "Nerd fonts (JetBrainsMono, CaskaydiaMono: what Omarchy's terminal configs use)"
fonts=$OMARCHY_HOME/.local/share/fonts
for family in JetBrainsMono CascadiaMono; do
  if ! fc-list | grep -qi "${family/CascadiaMono/CaskaydiaMono}"; then
    github_release_download ryanoasis/nerd-fonts "$NERD_FONTS_VERSION" "$family.tar.xz"
    mkdir -p "$fonts" && tar -xJf "$DOWNLOADS/$family.tar.xz" -C "$fonts" --wildcards '*.ttf'
    note "installed $family nerd font"
  fi
done
fc-cache -f "$fonts" >/dev/null

# Interactive and non-interactive shells started by the desktop must see
# OMARCHY_PATH and $OMARCHY_PATH/bin; upstream's skel bashrc sources the same
# file. The block goes at the very top, before the interactive guard.
begin='# >>> omarchy-ubuntu env-bootstrap >>>'
end='# <<< omarchy-ubuntu env-bootstrap <<<'
if ! grep -qF "$begin" "$OMARCHY_HOME/.bashrc"; then
  log "env-bootstrap block in ~/.bashrc"
  backup_once "$OMARCHY_HOME/.bashrc"
  tmp=$(mktemp)
  {
    echo "$begin"
    echo "# OMARCHY_PATH comes from /etc/omarchy.conf; env-bootstrap puts \$OMARCHY_PATH/bin on PATH."
    echo "[ -r \"\$HOME/.local/share/omarchy/default/bash/env-bootstrap\" ] && . \"\$HOME/.local/share/omarchy/default/bash/env-bootstrap\""
    echo "$end"
    echo
    cat "$OMARCHY_HOME/.bashrc"
  } >"$tmp"
  cat "$tmp" >"$OMARCHY_HOME/.bashrc"
  rm -f "$tmp"
fi

# The uwsm session builds its environment from ~/.config/uwsm/env (the PPA's
# uwsm 0.26 ignores /usr/share/uwsm/env.d, which upstream uses). The file is
# read by /bin/sh, so keep it POSIX: no `source`, no `&>`, no bash-only evals.
env_file=$OMARCHY_HOME/.config/uwsm/env
mkdir -p "$(dirname "$env_file")"
touch "$env_file"
if ! grep -qF "$begin" "$env_file"; then
  log "env-bootstrap block in $env_file"
  backup_once "$env_file"
  cat >>"$env_file" <<EOF

$begin
# Same role as upstream's /usr/share/uwsm/env.d/10-omarchy. Loaded by /bin/sh: keep it POSIX.
[ -r "\$HOME/.local/share/omarchy/default/bash/env-bootstrap" ] && . "\$HOME/.local/share/omarchy/default/bash/env-bootstrap"
export TERMINAL=xdg-terminal-exec
$end
EOF
fi
if ! sh -n "$env_file" 2>/dev/null || grep -qE '^\s*source |&>' "$env_file"; then
  warn "$env_file has bash-only syntax; uwsm loads it with /bin/sh and the session will not start"
fi

mkdir -p "$OMARCHY_HOME/.local/state/omarchy" "$OMARCHY_HOME/.cache/omarchy" "$OMARCHY_HOME/.config/omarchy"
note "state dirs ready"
