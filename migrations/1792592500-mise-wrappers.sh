#!/bin/bash
# Upstream's 1791382872 retires the wrappers omarchy-mise-install wrote for the
# default tools, matched byte for byte against its templates. The wrappers this
# port's patch wrote (the binary resolved through `mise which`) match none of
# them, so they would stay in ~/.local/bin ahead of the lazy shims and put
# `tool = "latest"` back in the user's config at every run. The same list and
# the same rule with the port's template, and what upstream does around it
# (the shims first, `mise unuse` after), as this runs before or after its own.
#
# Pending (75) until step 57 has the declarations in place (4.5 and later) and
# upstream's own retirement has run: the migrations before it still write
# wrappers through omarchy-mise-install, in the port's form on this branch.
[[ -f /etc/mise/conf.d/omarchy-tools.toml ]] || exit 75
[[ -f $HOME/.local/state/omarchy/migrations/1791382872.sh ]] || exit 75
command -v mise >/dev/null || exit 0

port_wrapper_template() { # <package> <command>, quoted as the writer did since 4.0.4
  local package=$1 bin=$2 package_arg bin_arg
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
  printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet %s || exit 1\nbin_path=$(mise which --tool %s %s 2>/dev/null) || bin_path=%s\nexec mise x %s -- "$bin_path" "$@"\n' \
    "$package_arg" "$package_arg" "$bin_arg" "$bin_arg" "$package_arg"
}

port_wrapper() { # <command> <package>: the wrapper is the port's, untouched
  local wrapper=$HOME/.local/bin/$1
  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || return 1
  (( $(stat -c%s "$wrapper") <= 1024 )) || return 1
  cmp -s "$wrapper" <(port_wrapper_template "$2" "$1")
}

removed=()
remove_port_wrapper() {
  local command=$1 package
  shift
  for package in "$@"; do
    if port_wrapper "$command" "$package"; then
      rm -f "$HOME/.local/bin/$command"
      removed+=("$package")
      return
    fi
  done
}

# The shims before the wrappers go, unless the user opted out of the preinstalls.
if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  mise reshim --system
fi

remove_port_wrapper codex codex aqua:openai/codex npm:@openai/codex
remove_port_wrapper claude claude aqua:anthropics/claude-code
remove_port_wrapper crush crush aqua:charmbracelet/crush
remove_port_wrapper agy antigravity-cli aqua:google-antigravity/antigravity-cli gemini npm:@google/gemini-cli
remove_port_wrapper gh gh github-cli aqua:cli/cli
remove_port_wrapper copilot copilot aqua:github/copilot-cli github:github/copilot-cli npm:@github/copilot
remove_port_wrapper opencode opencode aqua:anomalyco/opencode
remove_port_wrapper playwright playwright npm:playwright
remove_port_wrapper playwright-cli playwright npm:playwright
remove_port_wrapper pi pi aqua:earendil-works/pi github:earendil-works/pi npm:@earendil-works/pi-coding-agent
remove_port_wrapper omp oh-my-pi github:can1357/oh-my-pi
remove_port_wrapper grok grok npm:@xai-official/grok
remove_port_wrapper ghui ghui npm:@kitlangton/ghui
remove_port_wrapper hunk hunk aqua:modem-dev/hunk
remove_port_wrapper hey hey-cli github:basecamp/hey-cli
remove_port_wrapper ori ori github:OpenRouterLabs/ori-releases
remove_port_wrapper cf npm:cf
remove_port_wrapper cursor-agent cursor-agent
remove_port_wrapper basecamp basecamp github:basecamp/basecamp-cli
remove_port_wrapper muse muse 'http:muse[url=https://api.meta.ai/muse-launcher.sh,bin=muse,version_list_url=https://api.meta.ai/muse-code/channels/muse-stable,version_json_path=.version]'

# Each wrapper's `mise use -g` left `tool = "latest"` in the user's config,
# which outranks Omarchy's declaration; only those exact requests go, a pinned
# version being the user's. After an opt-out they are what provides the tools.
if (( ${#removed[@]} )) && [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  mise unuse -g --no-prune "${removed[@]/%/@latest}"
fi
