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
)

# Run as is although they mention Arch tooling: each exits before touching it
# when the tooling is absent.
OMARCHY_MIGRATIONS_RUN=(
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
