#!/usr/bin/env bash

# Setup script for Modern Linux tools without micromamba
# - Derives install dir from this script's location (once, at source time)
# - Bakes that dir into setupMe and list_tools
# - Leaves no myDir-like variable in the parent shell

# --- Determine install directory once, during initial sourcing ---
_myName="${BASH_SOURCE:-${funcsourcetrace[1]%:*}}"
_myName=$(readlink -f -- "$_myName")
_myDir=$(dirname "$_myName")
_myDir_q=$(printf %q "$_myDir")   # shell-quoted version for safe eval

# --- Define functions with the resolved directory baked in ---

setup_linuxtools() {
  local myDir=$_myDir_q
  [[ "$_myDir_q" == "/" ]] && myDir=""

  if [[ ! -d "$myDir/opt/conda/bin" ]]; then
    echo "Error: Directory $myDir/opt/conda/bin does not exist"
    return 1
  fi

  # Architecture validation check
  local arch_ld=$(ls $myDir/lib*/ld-linux-*.so* 2>/dev/null | head -n1 | sed -E 's|.*/ld-linux-([^.]+)\.so.*|\1|; s/-/_/g')
  local arch_uname=$(uname -m)

  if [[ -n "$arch_ld" && "$arch_ld" != "$arch_uname" ]]; then
    echo "Warning: Architecture from the container ($arch_ld) does not match the machine ($arch_uname)"
    return 1
  fi

  # PATH and cache setup (only PATH and TEALDEER_CACHE_DIR are visible)
  [[ ":${PATH}:" != *":$myDir/opt/conda/bin:"* ]] && export PATH="$myDir/opt/conda/bin:${PATH}"
  export TEALDEER_CACHE_DIR="$myDir/opt/conda/.cache/tealdeer"

  local red
  red=$(tput setaf 1 2>/dev/null || echo '')
  local reset
  reset=$(tput sgr0 2>/dev/null || echo '')

  echo -e "🚀 Modern Linux tools are now available!

- Run '${red}list_tools${reset}' to view the complete list of new tools.
- For command usage, run '${red}<command> --help${reset}' (e.g., '${red}rg --help${reset}').
- For quick examples (except for goose and copilot-api),
      use '${red}tldr <command>${reset}' (e.g., '${red}tldr rg${reset}')."
  command -v git_delta &> /dev/null && echo -e "A wrapper function ${red}git_delta${reset} is defined. Run 'git_delta -h' for help"
  echo -e "Run '${red}remove_linuxtools${reset}' to remove the tools from PATH."

  # echo -e \"🚀 Modern Linux tools are now available!\"
  # echo -e \"\tRun \${red}list_tools\${reset} to view the complete list of new tools\"
}

# Run setup immediately when the script is sourced
setup_linuxtools
command -v tput &> /dev/null && alias glow='glow -w $(tput cols)'


eval "list_tools() {
  local myDir=$_myDir_q

  if command -v glow &> /dev/null && [ -f \"\$myDir/list-of-tools.md\" ]; then
     \$myDir/opt/conda/bin/mcat \$myDir/list-of-tools.md
  fi
}"

eval "remove_linuxtools() {
  local myDir=$_myDir_q
  [[ \"$_myDir_q\" == \"/\" ]] && myDir=\"\"
  local bin_dir=\"\$myDir/opt/conda/bin\"
  if [[ \":\${PATH}:\" == *\":\$bin_dir:\"* ]]; then
    export PATH=\"\$(echo \"\$PATH\" | sed -e \"s|:\${bin_dir}||g\" -e \"s|^\${bin_dir}:||\" -e \"s|:\${bin_dir}\$||\" -e \"s|^\${bin_dir}\$||\")\"
    echo \"Removed \$bin_dir from PATH\"
  else
    echo \"\$bin_dir is not in PATH\"
  fi
}"

# --- Clean up helper variables so they are not visible in the parent shell ---
unset _myName _myDir _myDir_q
