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
# The Ubuntu release (24.04 noble, 26.04 resolute): the sources and assets
# published per release follow it.
# shellcheck disable=SC1091,SC2034,SC2154  # os-release's own variables; UBUNTU_VERSION for the steps
read -r UBUNTU_VERSION UBUNTU_CODENAME < <(. /etc/os-release && echo "$VERSION_ID $VERSION_CODENAME")

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
    pkexec env OMARCHY_USER="$OMARCHY_USER" OMARCHY_CHANNEL="$OMARCHY_CHANNEL" REPO_DIR="$REPO_DIR" OMARCHY_INTEL_MEDIA="${OMARCHY_INTEL_MEDIA:-}" "$script" "$@"
  else
    sudo env OMARCHY_USER="$OMARCHY_USER" OMARCHY_CHANNEL="$OMARCHY_CHANNEL" REPO_DIR="$REPO_DIR" OMARCHY_INTEL_MEDIA="${OMARCHY_INTEL_MEDIA:-}" "$script" "$@"
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

# wayland_compat_cflags: what a build against Qt's private Wayland headers
# needs. Qt >= 6.10's qwayland-wayland.h declares wl_fixes, which only exists in
# libwayland >= 1.23's generated header; noble ships 1.22 (26.04 1.24). There a
# client header generated from a newer protocol XML, sharing the system one's
# WAYLAND_CLIENT_PROTOCOL_H guard, shadows it at compile time only: nothing
# needs wl_fixes at runtime.
wayland_compat_cflags() {
  pkg-config --atleast-version=1.23 wayland-client && return 0
  local compat=$SRC_DIR/quickshell-compat/include
  if [[ ! -f $compat/wayland-client-protocol.h ]]; then
    log "compat header from wayland $WAYLAND_XML_VERSION protocol XML" >&2
    mkdir -p "$compat" &&
      curl -fsSL -o "$SRC_DIR/quickshell-compat/wayland-$WAYLAND_XML_VERSION.xml" \
        "https://gitlab.freedesktop.org/wayland/wayland/-/raw/$WAYLAND_XML_VERSION/protocol/wayland.xml" &&
      cp /usr/include/wayland-client.h "$compat/wayland-client.h" &&
      wayland-scanner client-header "$SRC_DIR/quickshell-compat/wayland-$WAYLAND_XML_VERSION.xml" "$compat/wayland-client-protocol.h" ||
      return 1
  fi
  echo "-I$compat"
}

# cxx23: a compiler with C++23's <print> (libstdc++ 14). The default g++ where
# it is that new: the PPA's Hyprland libraries are built with it, and an older
# libstdc++ cannot link against them. noble's default is 13, so g++-14 there.
cxx23() {
  if (( $(g++ -dumpversion | cut -d. -f1) >= 14 )); then echo g++; else echo g++-14; fi
}

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

# git_checkout <dir> <url> <ref>: shallow clone at a tag or a commit, or switch an existing clone.
git_checkout() {
  local dir=$1 url=$2 ref=$3
  if [[ -d $dir/.git ]]; then
    # A repository moves now and then (tensaku's did): the clone follows the URL it is given.
    git -C "$dir" remote set-url origin "$url"
    # A tag fetched by name lands in FETCH_HEAD only: the checkout would sit on
    # it detached, describe would not name the pin, and the build steps that
    # compare the two would rebuild on every update.
    git -C "$dir" fetch --quiet --depth 1 origin "+refs/tags/$ref:refs/tags/$ref" 2>/dev/null ||
      git -C "$dir" fetch --quiet --depth 1 origin "$ref" 2>/dev/null || git -C "$dir" fetch --quiet --tags origin
    git -C "$dir" -c advice.detachedHead=false checkout --quiet "$ref" 2>/dev/null || git -C "$dir" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
  elif [[ $ref =~ ^[0-9a-f]{40}$ ]]; then
    # GitHub serves a commit by hash to fetch, which clone --branch cannot ask for.
    git init --quiet "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --quiet --depth 1 origin "$ref"
    git -C "$dir" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
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

# apt_source_active <uri> <suite>: an enabled apt source serves the suite from
# the URI. A release upgrade turns every third-party source off (Enabled: no)
# and leaves it at the old release, so its file alone says nothing. grep reads
# to the end: a -q quitting early would leave apt-get a SIGPIPE, which
# pipefail turns into a no.
apt_source_active() {
  # shellcheck disable=SC2016  # apt's own format fields
  apt-get indextargets --no-release-info --format '$(REPO_URI) $(RELEASE)' 2>/dev/null | grep -xF "${1%/}/ $2" >/dev/null
}

# ppa_source <owner/name>: the PPA, at this release. One the upgrade turned off
# stays as it left it, beside the new one.
ppa_source() {
  apt_source_active "https://ppa.launchpadcontent.net/$1/ubuntu" "$UBUNTU_CODENAME" && return 0
  # -n: add-apt-repository's own update shrugs off an index it could not
  # fetch; the apt_retry update after it does not.
  add-apt-repository -y -n "ppa:$1"
}

# removed_preinstalls: what Remove > Preinstalls took away (the names upstream's
# omarchy-remove-preinstalls drops), while its marker stands; nothing otherwise.
# Upstream's update never brings them back, so neither does a step here.
removed_preinstalls() {
  [[ -f $OMARCHY_HOME/.local/state/omarchy/preinstalls-removed ]] || return 0
  python3 "$REPO_DIR/lib/catalog.py" --calls "$OMARCHY_PATH" |
    awk -F'\t' '$2 == "drop" && $3 ~ /^bin\/omarchy-remove-preinstalls:/ { print $1 }' | sort -u
}

# base_apps: the companion apps upstream's base list carries at the checkout's
# tag, less the preinstalls the user removed.
base_apps() {
  local app removed
  removed=$(removed_preinstalls)
  for app in omacalc omawrite omacut hype monologue omasnap owe owe-lockfeed signed omarchy-hyprland-titlebars; do
    grep -qx "$app" "$OMARCHY_PATH/install/omarchy-base.packages" || continue
    grep -qx "$app" <<<"$removed" || echo "$app"
  done
}

# rewrite_unit <src> <dst>: upstream units point at /usr/bin/omarchy-*; the dev link keeps the
# scripts under /usr/share/omarchy/bin (a symlink to the checkout).
rewrite_unit() { sed -e "s|/usr/bin/omarchy-|/usr/share/omarchy/bin/omarchy-|g" "$1" >"$2"; }
