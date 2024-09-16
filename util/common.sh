#!/bin/bash

RELEASE_NAMESPACE='mmcai-system'
MMCLOUD_OPERATOR_NAMESPACE='mmcloud-operator-system'
PROMETHEUS_NAMESPACE='monitoring'

MMAI_CLUSTER_VERSION=0.2.0-rc2
MMAI_MANAGER_VERSION=0.2.0-rc2

CERT_MANAGER_VERSION='v1.15.3'
KUBEFLOW_VERSION='v1.9.0'
KUBEFLOW_ISTIO_VERSION='1.22'
NVIDIA_GPU_OPERATOR_VERSION='v24.3.0'

ANSIBLE_VENV='mmai-ansible'
ANSIBLE_INVENTORY_DATABASE_NODE_GROUP='mmai_database'

KUBEFLOW_MANIFEST='kubeflow-manifest.yaml'

ensure_prerequisites() {
    local script='ensure-prerequisites.sh'
    if ! curl -LfsSo $script https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/$script; then
        echo "Error getting script: $script"
        return 1
    fi
    chmod +x $script
    ./$script
}

prompt_default_yn() {
    local prompt="$1"
    local default="$2"
    local response
    while true; do
        read -p "$prompt" response
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
        case "$response" in
            y|yes ) return 0;;
            n|no ) return 1;;
            * ) echo "Invalid response. Please enter 'y' or 'n'.";;
        esac
    done
}

build_kubeflow() {
    if (( $# == 1 )) && [[ "$1" != "" ]] && [[ -d "$1" ]]; then
        # Use the specified log file.
        local base_dir=$1
    else
        return 1
    fi

    git clone https://github.com/kubeflow/manifests.git $base_dir/kubeflow --branch $KUBEFLOW_VERSION

    # From DeepOps: Change the default Istio Ingress Gateway configuration to support NodePort for ease-of-use in on-prem
    path_istio_version=${KUBEFLOW_ISTIO_VERSION#v}
    path_istio_version=${path_istio_version//./-}
    sed -i 's:ClusterIP:NodePort:g' "$base_dir/kubeflow/common/istio-$path_istio_version/istio-install/base/patches/service.yaml"

    # From DeepOps: Make the Kubeflow cluster allow insecure http instead of https
    # https://github.com/kubeflow/manifests#connect-to-your-kubeflow-cluster
    sed -i 's:JWA_APP_SECURE_COOKIES=true:JWA_APP_SECURE_COOKIES=false:' "$base_dir/kubeflow/apps/jupyter/jupyter-web-app/upstream/base/params.env"
    sed -i 's:VWA_APP_SECURE_COOKIES=true:VWA_APP_SECURE_COOKIES=false:' "$base_dir/kubeflow/apps/volumes-web-app/upstream/base/params.env"
    sed -i 's:TWA_APP_SECURE_COOKIES=true:TWA_APP_SECURE_COOKIES=false:' "$base_dir/kubeflow/apps/tensorboard/tensorboards-web-app/upstream/base/params.env"

    kustomize build $base_dir/kubeflow/example > $base_dir/$KUBEFLOW_MANIFEST
}
