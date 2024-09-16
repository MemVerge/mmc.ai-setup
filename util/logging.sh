#!/bin/bash

echo_green() {
  local lightgreen='\033[1;32m'
  local nocolor='\033[0m'
  echo -e "${lightgreen}$1${nocolor}"
}

echo_red() {
  local lightred='\033[1;31m'
  local nocolor='\033[0m'
  echo -e "${lightred}$1${nocolor}"
}

file_timestamp() {
  local python=$(which python3 || which python)
  $python -c "from datetime import datetime; print(datetime.now().strftime('%Y%m%d-%H%M%S%f'))"
}

log_timestamp() {
  local python=$(which python3 || which python)
  $python -c "from datetime import datetime; print(datetime.now().isoformat(timespec='microseconds'))"
}

log_good() {
  echo_green "[$0: $(log_timestamp)] $1"
}

log() {
  local lightgrey='\033[0;37m'
  local darkgrey='\033[1;30m'
  local nocolor='\033[0m'
  echo -e "${darkgrey}[$0: $(log_timestamp)] $1${nocolor}"
}

log_bad() {
  echo_red "[$0: $(log_timestamp)] $1"
}

div() {
  echo "---"
}

set_log_file() {
  if (( $# == 1 )) && [[ "$1" != "" ]]; then
    # Use the specified log file.
    local log_file="$1"
  else
    return 1
  fi
  # Capture STDOUT and STDERR to a log file, and display to the terminal.
  exec &> >(tee -a "$log_file")
}

unset_log_file() {
  exec &> /dev/tty
}
