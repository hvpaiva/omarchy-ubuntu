#!/bin/bash
# What Omarchy's omarchy-settings package does in /etc/skel and /usr/share,
# done in $HOME: the glyph font, the env-bootstrap hooks, state dirs, nerd fonts.
source "${REPO_DIR:?}/lib/common.sh"
need_user

bootstrap="$OMARCHY_PATH/default/bash/env-bootstrap"
[[ -r $bootstrap ]] || die "Omarchy checkout not found at $OMARCHY_PATH (run install/30-omarchy-checkout.sh)"

begin='# >>> omarchy-ubuntu env-bootstrap >>>'
end='# <<< omarchy-ubuntu env-bootstrap <<<'

# The uwsm session takes its environment from upstream's own
# /usr/share/uwsm/env.d/10-omarchy, which step 55 links and uwsm reads since
# 0.26.1. An older uwsm (26.04's 0.25.2) reads only ~/.config/uwsm/env, where a
# block sources the same file. That file is read by /bin/sh, so keep it POSIX:
# no `source`, no `&>`, no bash-only evals. The block from before step 55 linked
# the file goes once the link is there. With --uwsm-env, only this.
uwsm_env() {
  local env_file=$OMARCHY_HOME/.config/uwsm/env version='' wanted=0 block tmp
  apt_installed uwsm && version=$(dpkg-query -W -f='${Version}' uwsm)
  if [[ -n $version ]] && dpkg --compare-versions "$version" lt 0.26.1; then
    wanted=1
  fi
  block=$(printf '%s\n' "$begin" \
    "# uwsm older than 0.26.1 reads no env.d: upstream's session env, from here." \
    '[ -r /usr/share/uwsm/env.d/10-omarchy ] && . /usr/share/uwsm/env.d/10-omarchy' "$end")
  if [[ -f $env_file ]] && grep -qF "$begin" "$env_file"; then
    if (( wanted )) && [[ $(awk -v b="$begin" -v e="$end" '$0 == b { on = 1 } on { print } $0 == e { on = 0 }' "$env_file") == "$block" ]]; then
      return 0
    fi
    (( wanted )) || [[ -e /usr/share/uwsm/env.d/10-omarchy ]] || return 0
    tmp=$(mktemp)
    awk -v b="$begin" -v e="$end" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$env_file" >"$tmp"
    cat "$tmp" >"$env_file"
    rm -f "$tmp"
    note "env-bootstrap block taken out of $env_file"
  fi
  if (( wanted )); then
    log "env-bootstrap block in $env_file (uwsm $version reads no env.d)"
    mkdir -p "$(dirname "$env_file")"
    touch "$env_file"
    backup_once "$env_file"
    printf '\n%s\n' "$block" >>"$env_file"
  fi
  if [[ -f $env_file ]] && { ! sh -n "$env_file" 2>/dev/null || grep -qE '^\s*source |&>' "$env_file"; }; then
    warn "$env_file has bash-only syntax; uwsm loads it with /bin/sh and the session will not start"
  fi
}
if [[ ${1:-} == --uwsm-env ]]; then
  uwsm_env
  exit 0
fi

log "Omarchy glyph font"
install -Dm644 "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" "$OMARCHY_HOME/.local/share/fonts/omarchy/omarchy.ttf"
fc-cache -f "$OMARCHY_HOME/.local/share/fonts/omarchy" >/dev/null

log "Nerd fonts $NERD_FONTS_VERSION (JetBrainsMono, CaskaydiaMono: what Omarchy's terminal configs use)"
fonts=$OMARCHY_HOME/.local/share/fonts
# The archives carry no version in their name, so the installed one is
# stamped here and the cached archive dropped when it moves.
stamp=$fonts/.nerd-fonts-version
for family in JetBrainsMono CascadiaMono; do
  # grep reads fc-list to its end: with -q it would quit at the first match,
  # fc-list would die of SIGPIPE and pipefail would call the font missing.
  if ! fc-list | grep -i "${family/CascadiaMono/CaskaydiaMono}" >/dev/null || [[ $(cat "$stamp" 2>/dev/null) != "$NERD_FONTS_VERSION" ]]; then
    rm -f "$DOWNLOADS/$family.tar.xz"
    github_release_download ryanoasis/nerd-fonts "$NERD_FONTS_VERSION" "$family.tar.xz"
    mkdir -p "$fonts" && tar -xJf "$DOWNLOADS/$family.tar.xz" -C "$fonts" --wildcards '*.ttf'
    note "installed $family nerd font $NERD_FONTS_VERSION"
  fi
done
mkdir -p "$fonts" && echo "$NERD_FONTS_VERSION" >"$stamp"
fc-cache -f "$fonts" >/dev/null

# Interactive and non-interactive shells started by the desktop must see
# OMARCHY_PATH and $OMARCHY_PATH/bin; upstream's skel bashrc sources the same
# file. The block goes at the very top, before the interactive guard.
# skipped when ~/.bashrc already sources env-bootstrap on its own (a dotfiles bashrc does)
if ! grep -qF "$begin" "$OMARCHY_HOME/.bashrc" && ! grep -qF 'default/bash/env-bootstrap' "$OMARCHY_HOME/.bashrc"; then
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

uwsm_env

mkdir -p "$OMARCHY_HOME/.local/state/omarchy" "$OMARCHY_HOME/.cache/omarchy" "$OMARCHY_HOME/.config/omarchy"
note "state dirs ready"
