#!/bin/bash
# The Install menu's mise recipes went through omarchy-mise-install before they
# declared their tool in the port's own file: a wrapper in ~/.local/bin that
# runs `mise use -g` at every start, so a tool the user took out of their
# config.toml came back, installed again, at the next shell (starship, whose
# command Omarchy's bash init runs). Those wrappers go, matched byte for byte
# against what the writer produced, in upstream's form or the port's (patch
# mise-wrappers); one the user edited stays. helix's, whose command is not the
# tool's binary, becomes the recipe's launcher while mise has helix. The line
# a wrapper wrote in config.toml stays: it may be the user's own.

# shellcheck disable=SC1003,SC2016  # the writer's text, its quoting included
wrapper_template() { # <form: upstream|port> <package> <bin>, quoted as the writer did since 4.0.4
  local form=$1 package=$2 bin=$3 package_arg bin_arg
  printf -v package_arg '%q' "$package"
  printf -v bin_arg '%q' "$bin"
  case $package in
    *'$'* | *'`'* | *'"'* | *'\'* | *'!'* | *[[:cntrl:]]*) ;;
    *) package_arg="\"$package\"" ;;
  esac
  case $bin in
    *'$'* | *'`'* | *'"'* | *'\'* | *'!'* | *[[:cntrl:]]*) ;;
    *) bin_arg="\"$bin\"" ;;
  esac
  if [[ $form == port ]]; then
    printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet %s || exit 1\nbin_path=$(mise which --tool %s %s 2>/dev/null) || bin_path=%s\nexec mise x %s -- "$bin_path" "$@"\n' \
      "$package_arg" "$package_arg" "$bin_arg" "$bin_arg" "$package_arg"
  else
    printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet %s || exit 1\nexec mise x %s -- %s "$@"\n' \
      "$package_arg" "$package_arg" "$bin_arg"
  fi
}

recipe_wrapper() { # <command> <package> <bin>: the writer's, untouched
  local wrapper=$HOME/.local/bin/$1 form
  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || return 1
  (( $(stat -c%s "$wrapper") <= 1024 )) || return 1
  for form in upstream port; do
    cmp -s "$wrapper" <(wrapper_template "$form" "$2" "$3") && return 0
  done
  return 1
}

removed=()
retire() { # <command> <package> [bin]
  local command=$1 package=$2 bin=${3:-$1}
  recipe_wrapper "$command" "$package" "$bin" || return 0
  rm -f "$HOME/.local/bin/$command"
  if [[ $command != "$bin" ]] && command -v mise >/dev/null && mise where "$package" >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec %s "$@"\n' "$bin" >"$HOME/.local/bin/$command"
    chmod 755 "$HOME/.local/bin/$command"
  fi
  removed+=("$package")
}

retire helix helix hx
retire bw bitwarden
retire symfony github:symfony-cli/symfony-cli
retire lazygit lazygit
retire lazydocker lazydocker
retire starship starship
retire usage usage
retire dua dua

if (( ${#removed[@]} )); then
  echo "Removed the mise wrappers that put their tool back at every start: ${removed[*]}."
  echo "A 'tool = \"latest\"' line they wrote in ~/.config/mise/config.toml stays; take it out there to drop the tool."
fi
