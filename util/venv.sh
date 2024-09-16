#!/bin/bash

MMAI_VENV_DIR=".mmai-venvs"

cvenv() {
  if (( $# == 1 )); then
    venvpath=$MMAI_VENV_DIR/$1
    if [[ ! -d $venvpath && ! -f $venvpath ]]; then
      local python=$(which python3 || which python)
      $python -m venv $venvpath
    else
      echo "Cannot create venv: name already exists"
      return 1
    fi
  else
    echo "Cannot create venv: 1 argument expected, $# received"
    return 1
  fi
}

avenv() {
  if (( $# == 1 )); then
    activatevenvpath=$MMAI_VENV_DIR/$1/bin/activate
    if [[ -f $activatevenvpath ]]; then
      source $activatevenvpath
    else
      echo "Cannot activate venv: venv does not exist"
      return 1
    fi
  else
    echo "Cannot activate venv: 1 argument expected, $# received"
    return 1
  fi
}

lvenv() {
  ls $MMAI_VENV_DIR
}

dvenv() {
  deactivate
}

rvenv() {
  if (( $# == 1 )); then
    venvpath=$MMAI_VENV_DIR/$1
    if [[ -d $venvpath ]]; then
      rm -rf $venvpath
    else
      echo "Cannot remove venv: venv does not exist"
      return 1
    fi
  else
    echo "Cannot remove venv: 1 argument expected, $# received"
    return 1
  fi
}
