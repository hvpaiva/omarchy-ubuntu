#!/bin/bash
# Shared helpers for the bootstrap steps. Source, do not execute.

set -euo pipefail

REPO_DIR=${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=units.sh
source "$REPO_DIR/lib/units.sh"

OMARCHY_USER=${OMARCHY_USER:-${SUDO_USER:-${PKEXEC_UID:+$(id -un "$PKEXEC_UID")}}}
OMARCHY_USER=${OMARCHY_USER:-$(id -un)}
OMARCHY_HOME=$(getent passwd "$OMARCHY_USER" | cut -d: -f6)
# The channel is the user's, so it is read once the user is known.
# shellcheck source=channel.sh
source "$REPO_DIR/lib/channel.sh"
OMARCHY_PATH=${OMARCHY_PATH:-$OMARCHY_HOME/.local/share/omarchy}
SRC_DIR=${SRC_DIR:-$OMARCHY_HOME/.local/src}
QT_DIR=${QT_DIR:-$OMARCHY_HOME/.local/opt/Qt/$QT_VERSION/gcc_64}
# shellcheck disable=SC2034  # for the steps that source this
LOCAL_BIN=$OMARCHY_HOME/.local/bin
DOWNLOADS=$REPO_DIR/downloads
JOBS=${JOBS:-$(nproc)}

log() { printf '\e[32m==> %s\e[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\e[33m!!  %s\e[0m\n' "$*" >&2; }
die() { printf '\e[31mxx  %s\e[0m\n' "$*" >&2; exit 1; }

need_root() { (( EUID == 0 )) || die "this step must run as root (the bootstrap runs it through pkexec or sudo)"; }
need_user() { (( EUID != 0 )) || die "this step must run as the desktop user, not root"; }

# Run a repo script as root. On a terminal, sudo: its cached credential covers every
# root script of the run with one password (dots setup keeps it alive). Without a
# terminal, pkexec goes through the session's polkit agent (the omarchy-shell dialog).
# Either way the target user is passed explicitly.
run_root() {
  local script=$1
  shift
  if (( EUID == 0 )); then
    OMARCHY_USER=$OMARCHY_USER "$script" "$@"
  elif [[ ! -t 0 && -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && command -v pkexec >/dev/null && [[ ${OMARCHY_ROOT_VIA:-pkexec} == pkexec ]]; then
    pkexec env OMARCHY_USER="$OMARCHY_USER" OMARCHY_CHANNEL="$OMARCHY_CHANNEL" REPO_DIR="$REPO_DIR" "$script" "$@"
  else
    sudo env OMARCHY_USER="$OMARCHY_USER" OMARCHY_CHANNEL="$OMARCHY_CHANNEL" REPO_DIR="$REPO_DIR" "$script" "$@"
  fi
}

# install_file <mode> <dest> < content : write only when the content changed.
install_file() {
  local mode=$1 dest=$2 tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    note "unchanged $dest"
  else
    install -D -m "$mode" -o root -g root "$tmp" "$dest"
    note "written   $dest"
  fi
  rm -f "$tmp"
}

# backup_once <file>: keep the pre-port copy next to the file, only the first time.
backup_once() {
  if [[ -f $1 && ! -e $1.bak-omarchy ]]; then
    cp -a "$1" "$1.bak-omarchy"
    note "backup    $1.bak-omarchy"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# quietly <command...>: its output only when it fails. The build tools put
# their errors on stdout, so `>/dev/null` would leave a failed step mute.
quietly() {
  local out status=0
  out=$("$@" 2>&1) || status=$?
  (( status == 0 )) || printf '%s\n' "$out" >&2
  return "$status"
}

# Launchpad's PPA mirrors answer 503 in bursts that outlast apt's own per-file
# retries; a later apt-get picks up where the last one stopped, the archives
# already fetched staying in its cache. Error-Mode=any: an index `update`
# could not fetch is otherwise a warning and exit 0, and the install after it
# finds no candidate (as pacman -Sy, upstream's, which fails on a lost sync).
apt_retry() { # apt_retry <apt-get arguments...>
  local try
  for try in 1 2 3 4 5; do
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 -o APT::Update::Error-Mode=any "$@" && return 0
    (( try < 5 )) || return 1
    warn "apt-get failed (attempt $try of 5); again in 60 s"
    sleep 60
  done
}

# git_checkout <dir> <url> <ref>: shallow clone at a tag, or switch an existing clone.
git_checkout() {
  local dir=$1 url=$2 ref=$3
  if [[ -d $dir/.git ]]; then
    git -C "$dir" fetch --quiet --depth 1 origin "$ref" 2>/dev/null || git -C "$dir" fetch --quiet --tags origin
    git -C "$dir" -c advice.detachedHead=false checkout --quiet "$ref" 2>/dev/null || git -C "$dir" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
  else
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ref" "$url" "$dir"
  fi
}

# github_release_download <repo> <tag> <asset> : into $DOWNLOADS, cached.
github_release_download() {
  local repo=$1 tag=$2 asset=$3
  mkdir -p "$DOWNLOADS"
  [[ -s $DOWNLOADS/$asset ]] && return 0
  curl -fsSL -o "$DOWNLOADS/$asset" "https://github.com/$repo/releases/download/$tag/$asset"
}

# apt_installed <pkg>
apt_installed() { [[ $(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null) == ?i* ]]; }

# rewrite_unit <src> <dst>: upstream units point at /usr/bin/omarchy-*; the dev link keeps the
# scripts under /usr/share/omarchy/bin (a symlink to the checkout).
rewrite_unit() { sed -e "s|/usr/bin/omarchy-|/usr/share/omarchy/bin/omarchy-|g" "$1" >"$2"; }
