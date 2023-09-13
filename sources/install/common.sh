#!/bin/bash
# Author: The Exegol Project

# Functions and commands that will be retried multiple times to counter random network issues when building
CATCH_AND_RETRY_COMMANDS=("curl" "wget" "apt-fast" "git" "go" "git" "apt-get")

export RED='\033[1;31m'
export BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export NOCOLOR='\033[0m'

### Echo functions

function colorecho () {
    echo -e "${BLUE}[EXEGOL] $*${NOCOLOR}"
}

function criticalecho () {
    echo -e "${RED}[EXEGOL ERROR] $*${NOCOLOR}" 2>&1
    exit 1
}

function criticalecho-noexit () {
    echo -e "${RED}[EXEGOL ERROR] $*${NOCOLOR}" 2>&1
}

### Support functions

function add-to-list() {
  echo $1 >> "/.exegol/installed_tools.csv"
}

function add-aliases() {
    colorecho "Adding aliases for: $*"
    # Removing add empty lines and the last trailing newline if any, and adding a trailing newline.
    grep -vE "^\s*$" "/root/sources/assets/zsh/aliases.d/$*" | tee -a /opt/.exegol_aliases
}

function add-history() {
    colorecho "Adding history commands for: $*"
    # Removing add empty lines and the last trailing newline if any, and adding a trailing newline.
    grep -vE "^\s*$" "/root/sources/assets/zsh/history.d/$*" | tee -a ~/.zsh_history
}

function add-test-command() {
    colorecho "Adding build pipeline test command: $*"
    echo "$*" >> "/.exegol/build_pipeline_tests/all_commands.txt"
}

function fapt() {
    colorecho "Installing apt package(s): $*"
    apt-fast install -y --no-install-recommends "$@"
}

function fapt-noexit() {
    # This function tries the same thing as fapt but doesn't exit in case something's wrong.
    # Example: a package exists in amd64 but not arm64. I didn't find a way of knowing that beforehand.
    colorecho "Installing (no-exit) apt package(s): $*"
    apt-get install -y --no-install-recommends "$*" || echo -e "${RED}[EXEGOL ERROR] Package(s) $* probably doesn't exist for architecture $(uname -m), or no installation candidate was found, or some other error...${NOCOLOR}" 2>&1
}

function fapt-history() {
    fapt "$@"
    for i in "$@"; do
        add-history "$i"
    done
}

function fapt-aliases() {
    fapt "$@"
    for i in "$@"; do
        add-aliases "$i"
    done
}

function fapt-history-aliases() {
    fapt "$@"
    for i in "$@"; do
        add-history "$i"
        add-aliases "$i"
    done
}

function set_go_env() {
    colorecho "Setting golang environment variables for installation"
    export GO111MODULE=on
    export PATH=$PATH:/usr/local/go/bin:/root/.local/bin
}

function set_ruby_env() {
    colorecho "Setting ruby environment variables for installation"
    source /usr/local/rvm/scripts/rvm
    rvm use 3.0.0@default
}

function install_pipx_git_tool() {
    colorecho "Installing $2 with pipx"
    python3 -m pipx install $1
    if [ "$3" ]
    then
        add-test-command $3
    fi
    if [[ "$*" == *"history"* ]]
    then
        add-history $2
    fi
}

function install_go_tool() {
    colorecho "Installing $2 with Golang"
    go install -v $1
    if [ "$3" ]
    then
        add-test-command $3
    fi
    if [[ "$*" == *"history"* ]]
    then
        add-history $2
    fi
}

function install_pipx_tool() {
    colorecho "Installing $1 with pipx"
    python3 -m pipx install $1
    if [ "$2" ]
    then
        add-test-command $2
    fi
    if [[ "$*" == *"history"* ]]
    then
        add-history $1
    fi
 }

function install_apt_tool() {
    colorecho "Installing $1 with apt"
    fapt $1
    if [ "$2" ]
    then
        add-test-command $2
    fi
    if [[ "$*" == *"history"* ]]
    then
        add-history $1
    fi

    if [[ "$*" == *"aliases"* ]]
    then
        add-aliases $1
    fi
}

### Catch & retry definitions

function catch_and_retry() {
  local retries=5
  # wait time = scale_factor x (base_exponent ^ retry)
  local scale_factor=2  # scaling factor
  local base_exponent=4 # base of the exponent
  # 1st retry: 2×4^1 = 2×4    = 8 seconds
  # 2nd retry: 2×4^2 = 2×16   = 32 seconds
  # 3rd retry: 2×4^3 = 2×64   = 128 seconds
  # 4th retry: 2×4^4 = 2×256  = 512 seconds
  # 5th retry: 2×4^5 = 2×1024 = 2048 seconds
  local max_wait_time=0
  local command="$@"
  for ((i=1; i<=retries; i++)); do
    # sh -c is used instead of an "eval" in order to avoid an infinite loop
    #  for instance, with an "eval", "wget" would point to the "wget" function defined with define_retry_function()
    sh -c "$command"
    # If command exits successfully, no need for more retries
    if [[ $? -eq 0 ]]; then
      return 0
    fi
    # Calculate the exponential backoff time
    local wait_time=$((scale_factor * (base_exponent ** i)))
    # Cap it at max_wait_time
    wait_time=$(( wait_time > max_wait_time ? max_wait_time : wait_time ))
    criticalecho-noexit "Command failed (attempt $i/$retries). Retrying in $wait_time seconds..."
    sleep "$wait_time"
  done
  criticalecho-noexit "Command failed definitively after $retries attempts."
  return 1
}

function define_retry_function() {
  local original_command=$1
  eval "
  function $original_command() {
    colorecho 'Catch & retry function for: $1'
    catch_and_retry \"$original_command \$@\"
  }
  "
}

# Dynamically create wrappers
for cmd in "${CATCH_AND_RETRY_COMMANDS[@]}"; do
  define_retry_function "$cmd"
done