#!/bin/bash
# What the updater does with migrations that reach for Arch. Source, do not execute.
#
# Upstream's update runs every new migration without a question. The port can
# only do the same once each migration that mentions pacman or Arch's boot
# stack has been read and recorded here: one that only does Arch's work is
# marked done without running, with what the port does instead noted next to
# it; one that steps aside on its own on a machine without that tooling runs
# as is. A migration that matches neither list stops the updater with a
# question, which is the signal to read it and add it.

# Marked done, never run.
OMARCHY_MIGRATIONS_ARCH_ONLY=(
  1787666837.sh # Dell XPS 13 sidecar amps: a skip recipe, and dell-xps13-sidecar-amps-apply does not exist here; noble's kernel drives the speakers
  1788279117.sh # YT6801 DKMS driver retirement through pacman -Qq; the port never installed it, Ubuntu's kernel drives the NIC
  1788862626.sh # Elgato Cam Link 4K relay: noble's v4l2loopback-ctl 0.12 cannot add the device; not ported (issue #12)
  1788996284.sh # repairs omarchy-nvim's clipboard provider through pacman; the port has no omarchy-nvim package
  1790917620.sh # N1x: reorders /etc/pacman.conf; no pacman and no aarch64 here
  1790953795.sh # ASUS ProArt P14 N1x: a Limine command-line drop-in and limine-mkinitcpio
  1790984400.sh # Dell XPS 16 N1x: the same Limine drop-in
  1790984600.sh # N1x USB4/Thunderbolt: a Limine drop-in and a UKI rebuild
  1790984700.sh # N1x GPU memory: a Limine drop-in and a UKI rebuild
  1791077437.sh # N1x: linux-omarchy-n1x through pacman, mkinitcpio and limine; the port is amd64 on Ubuntu's kernel
  1791152480.sh # N1x: a pacman hook and a rescue UKI through limine-entry-tool, neither ever here
  1791403252.sh # reorders /etc/pacman.conf so Omarchy's repository comes first
  1791408113.sh # ASUS ProArt P14 N1x: hid_asus fnlock on linux-omarchy-n1x and limine-mkinitcpio
  1791898365.sh # Limine boot menu timeout; Ubuntu boots with GRUB, and it would ask for sudo before finding no limine.conf
)

# Run as is although they mention Arch tooling: each exits before touching it
# when the tooling is absent.
OMARCHY_MIGRATIONS_RUN=(
  1788163635.sh # legacy passwordless-sudo grants: asks for sudo (and the helper's lock, which refuses Ubuntu's /run/lock) only without the marker the port's migration 1792592191 writes first
  1789928586.sh # exits unless aarch64 with /etc/default/limine
  1790517230.sh # exits unless a DGX Spark with limine-mkinitcpio on PATH
  1790917773.sh # exits unless the N1x console drop-in exists
  1790950659.sh # exits unless the N1x GPU drop-in exists
  1791581004.sh # rebuilds the Limine boot image; exits at once without limine-mkinitcpio
  1791621765.sh # the same, for the keyboard layout in the initramfs
  1791769486.sh # USB/Thunderbolt approval removal: limine, pacman.log and pacman -Qo sit behind guards false here; the user-level cleanup runs
  1791784278.sh # exits unless an NVIDIA N1x
)

migration_listed() {
  local name=$1 entry
  shift
  for entry in "$@"; do
    [[ $name == "$entry" ]] && return 0
  done
  return 1
}

migration_arch_only() { migration_listed "$1" "${OMARCHY_MIGRATIONS_ARCH_ONLY[@]}"; }
migration_runs_here() { migration_listed "$1" "${OMARCHY_MIGRATIONS_RUN[@]}"; }
