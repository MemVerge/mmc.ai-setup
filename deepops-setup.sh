#!/bin/bash

set -euo pipefail

curl -LfsSo logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/util/logging.sh

source logging.sh

## welcome message

div
log "Welcome to the MMC.AI DeepOps setup helper!"
div

## pull yq binary -- will need it to modify config settings later

YQ_BIN=yq_linux_amd64

function yq_install() {
  local yq_version=v4.44.1
  wget https://github.com/mikefarah/yq/releases/download/${yq_version}/${YQ_BIN}.tar.gz -O - | tar xz

  # Test installation
  log "yq version:"
  ./${YQ_BIN} --version
}

function yq_uninstall() {
  rm -rf ./yq*
  rm -rf ./install-man*
}

function yq_set() {
  ./${YQ_BIN} -i "$1" $2

  local var=$(echo "$1" | sed 's/=.*//')
  local yq_get=$(./${YQ_BIN} "$var" $2)

  log "yq set $1 in $2 -> $yq_get"
}

## Check that the parent directory is deepops

if [ "$(basename "$PWD")" != "deepops" ]; then
  log_bad "User is not currently in the deepops directory; please run this script from within '/deepops/'."
  exit 1
fi

## add an unqualified registry

cat << EOF > submodules/kubespray/roles/container-engine/cri-o/templates/unqualified.conf.j2
{%- set _unqualified_registries = ['docker.io'] -%}
{% for _registry in crio_registries if _registry.unqualified -%}
{% if _registry.prefix is defined -%}
{{ _unqualified_registries.append(_registry.prefix) }}
{% else %}
{{ _unqualified_registries.append(_registry.location) }}
{%- endif %}
{%- endfor %}

unqualified-search-registries = {{ _unqualified_registries | string }}
EOF

## modify relevant config values

yq_install

yq_set '.nvidia_driver_branch = "550"' roles/galaxy/nvidia.nvidia_driver/defaults/main.yml

yq_set '.container_manager = "crio"' config/group_vars/k8s-cluster.yml

yq_uninstall

## Set up ansible logs

rm -rf logs

mkdir logs

ANSIBLE_CFG=./ansible.cfg

if [[ "$(grep log_path $ANSIBLE_CFG)" -ne 0 ]]; then
  LOG_PATH=logs/k8s_deploy.log
  log "No log_path found in deepops/ansible.cfg, will set path to ./$LOG_PATH"

  # Create the logfile if it doesn't already exist
  touch $LOG_PATH
  echo "log_path = $(pwd)/$LOG_PATH" >> $ANSIBLE_CFG
  echo "display_args_to_stdout = True" >> $ANSIBLE_CFG
fi

div
log_good "Attempting Kubernetes setup..."
div
ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml

div
log_good "Kubernetes setup was successful!"
div
