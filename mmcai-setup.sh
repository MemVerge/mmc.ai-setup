#!/bin/bash

set -uo pipefail

ignore_errors=false

while getopts "i" option; do
    case $option in
        i ) ignore_errors=true;;
        * ) echo "Invalid option. Use -i to ignore errors."
    esac
done

if ! $ignore_errors; then
    set -e
fi

imports='
    common.sh
    logging.sh
    venv.sh
'
for import in $imports; do
    if ! curl -LfsSo $import https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/util/$import; then
        echo "Error getting script dependency: $import"
        exit 1
    fi
    source $import
done

ensure_prerequisites

MMAI_SETUP_LOG_DIR="mmai-setup-$(file_timestamp)"
mkdir -p $MMAI_SETUP_LOG_DIR
LOG_FILE="$MMAI_SETUP_LOG_DIR/mmai-setup.log"
set_log_file $LOG_FILE

TEMP_DIR=$(mktemp -d)
cleanup() {
    dvenv || true
    rm -rf $TEMP_DIR
}
trap cleanup EXIT

cvenv $ANSIBLE_VENV || true
avenv $ANSIBLE_VENV
pip install -q ansible

################################################################################

install_mmcai_manager=false
install_mmcai_cluster=false
install_nvidia_gpu_operator=false
install_kubeflow=false
install_cert_manager=false # Allow instead of kubeflow if not installing mmcai-manager.

confirm_selection=false

# Sanity check.
log "Getting Kubernetes version to check connectivity."
if ! kubectl version; then
    log_bad "Error getting version. Cannot proceed with setup."
    exit 1
else
    log_good "Got version successfully. Proceeding with setup."
fi

function helm_login() {
    # Extract creds.
    secret_json=$(
        kubectl get secret memverge-dockerconfig -n $RELEASE_NAMESPACE --output="jsonpath={.data.\.dockerconfigjson}" |
        base64 --decode
    )
    secret_user=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".username')
    secret_token=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".password')

    # Attempt login.
    if echo $secret_token | helm registry login ghcr.io/memverge -u $secret_user --password-stdin; then
        log_good "Helm login was successful."
    else
        log_bad "Helm login was unsuccessful."
        log_bad "Please provide an mmcai-ghcr-secret.yaml that allows helm login."
        div
        log "Content:"
        cat mmcai-ghcr-secret.yaml
        div
        exit 1
    fi
}

if [[ -f "mmcai-ghcr-secret.yaml" ]]; then
    div
    kubectl apply -f mmcai-ghcr-secret.yaml
    helm registry logout ghcr.io/memverge
    helm_login
    div

if kubectl get secret -n $RELEASE_NAMESPACE memverge-dockerconfig; then
    release_namespace_image_pull_secrets_detected=true
else
    release_namespace_image_pull_secrets_detected=false
    log_bad "MemVerge image pull secret in namespace $RELEASE_NAMESPACE not detected."
fi

if kubectl get secret -n $MMCLOUD_OPERATOR_NAMESPACE memverge-dockerconfig; then
    mmcloud_operator_namespace_image_pull_secrets_detected=true
else
    mmcloud_operator_namespace_image_pull_secrets_detected=false
    log_bad "MemVerge image pull secret in namespace $MMCLOUD_OPERATOR_NAMESPACE not detected."
fi

if ! $release_namespace_image_pull_secrets_detected \
|| ! $mmcloud_operator_namespace_image_pull_secrets_detected
then
    log_bad "Cannot proceed with setup."
    exit 1
fi

# Determine if cert-manager is installed.
cert_manager_detected() {
    kubectl get namespace cert-manager
}
if ! cert_manager_detected; then
    log "cert-manager not detected."
fi

# Determine if Kubeflow is installed.
kubeflow_detected() {
    kubectl get namespace kubeflow
}
if ! kubeflow_detected; then
    log "Kubeflow not detected."
fi

# Determine if nvidia-gpu-operator is installed.
nvidia_gpu_operator_detected() {
    helm list -n gpu-operator -a -q | grep gpu-operator
}
if ! nvidia_gpu_operator_detected; then
    log "NVIDIA GPU Operator not detected."
fi

# Determine if mmcai-cluster is installed.
mmcai_cluster_detected() {
    helm list -n mmcai-system -a -q | grep mmcai-cluster
}
if ! mmcai_cluster_detected; then
    log "MMC.AI Cluster not detected."
fi

# Determine if mmcai-manager is installed.
mmcai_manager_detected() {
    helm list -n mmcai-system -a -q | grep mmcai-manager
}
if ! mmcai_manager_detected; then
    log "MMC.AI Manager not detected."
fi

################################################################################

# Install mmcai-manager?
if ! mmcai_manager_detected; then
    div
    if prompt_default_yn "Install MMC.AI Manager [y/N]:" n; then
        install_mmcai_manager=true
    else
        install_mmcai_manager=false
    fi
fi

if $install_mmcai_manager || mmcai_manager_detected; then
    be_mmcai_manager=true
else
    be_mmcai_manager=false
fi

while $be_mmcai_manager && cert_manager_detected && ! kubeflow_detected; do
    echo "MMC.AI Manager requires Kubeflow, which provides cert-manager. Please uninstall existing cert-manager before continuing if you wish to install MMC.AI Manager."
    if prompt_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! cert_manager_detected; then
        log "cert-manager not detected."
    fi
    if ! kubeflow_detected; then
        log "Kubeflow not detected."
    fi
done

# Install mmcai-cluster?
if ! mmcai_cluster_detected; then
    if $be_mmcai_manager; then
        echo "MMC.AI Manager does not work without MMC.AI Cluster. MMC.AI Cluster will be installed."
        install_mmcai_cluster=true
    else
        div
        if prompt_default_yn "Install MMC.AI Cluster [y/N]:" n; then
            install_mmcai_cluster=true
        else
            install_mmcai_cluster=false
        fi
    fi
fi

if $install_mmcai_cluster || mmcai_cluster_detected; then
    be_mmcai_cluster=true
else
    be_mmcai_cluster=false
fi

if $install_mmcai_cluster && nvidia_gpu_operator_detected; then
    echo "MMC.AI Cluster requires NVIDIA GPU Operator installed with a specific configuration. If existing NVIDIA GPU Operator was not installed using this script, please uninstall existing NVIDIA GPU Operator before continuing."
    if prompt_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! nvidia_gpu_operator_detected; then
        log "NVIDIA GPU Operator not detected."
    fi
fi

# Install NVIDIA GPU Operator?
if ! nvidia_gpu_operator_detected; then
    if $be_mmcai_cluster; then
        echo "NVIDIA GPU Operator is required by MMC.AI Cluster. NVIDIA GPU Operator will be installed."
        install_nvidia_gpu_operator=true
    else
        div
        if prompt_default_yn "Install NVIDIA GPU Operator [y/N]:" n; then
            install_nvidia_gpu_operator=true
        else
            install_nvidia_gpu_operator=false
        fi
    fi
fi

if $install_mmcai_manager && kubeflow_detected; then
    echo "MMC.AI Manager requires Kubeflow installed with a specific configuration. If existing Kubeflow was not installed using this script, please uninstall existing Kubeflow before continuing."
    if prompt_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! kubeflow_detected; then
        log "Kubeflow not detected."
    fi
fi

# Install Kubeflow?
if ! kubeflow_detected; then
    if $be_mmcai_manager; then
        echo "Kubeflow is required by MMC.AI Manager. Kubeflow will be installed."
        install_kubeflow=true
    else
        div
        if prompt_default_yn "Install Kubeflow [y/N]:" n; then
            install_kubeflow=true
        else
            install_kubeflow=false
        fi
    fi
fi

if $install_kubeflow || kubeflow_detected; then
    be_kubeflow=true
else
    be_kubeflow=false
fi

# Install cert-manager?
if ! $be_kubeflow && ! cert_manager_detected; then
    if $be_mmcai_cluster; then
        echo "cert-manager is required by MMC.AI Cluster. cert-manager (Helm chart) will be installed."
        install_cert_manager=true
    else
        div
        if prompt_default_yn "Install cert-manager (Helm chart) [y/N]:" n; then
            install_cert_manager=true
        else
            install_cert_manager=false
        fi
    fi
fi

# Get Ansible inventory for components that need it.
if $install_mmcai_cluster || $install_kubeflow; then
    ANSIBLE_INVENTORY=''
    until [[ -e "$ANSIBLE_INVENTORY" ]]; do
        echo "Provide an Ansible inventory with the following Ansible host groups:"
        if $install_kubeflow; then
            echo "- [all] (used if installing Kubeflow)"
        fi
        if $install_mmcai_cluster; then
            echo "- [$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP] (used if installing MMC.AI Cluster)"
        fi
        read -p "Ansible inventory: " ANSIBLE_INVENTORY
        if ! [[ -e "$ANSIBLE_INVENTORY" ]]; then
            log_bad "Path does not exist."
        fi
    done

    if $install_mmcai_cluster; then
        MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | jq -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        while (( $(echo $MYSQL_NODE_HOSTNAME | wc -w) != 1 )); do
            log_bad "Wrong number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes in Ansible inventory."
            echo "Number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes must be 1. Please fix Ansible inventory before continuing."
            if prompt_default_yn "Continue setup [Y/n]:" y; then
                continue_setup=true
            else
                continue_setup=false
            fi
            if ! $continue_setup; then
                exit 0
            fi
            MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | jq -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        done

        if kubectl get secret -n $RELEASE_NAMESPACE mmai-mysql-secret &>/dev/null; then
            mysql_secret_exists=true
            log "Existing billing database secret found."
        else
            mysql_secret_exists=false
        fi

        if $mysql_secret_exists; then
            echo "Reuse existing billing database secret? If N/n, the existing database secret will be overwritten."
            if prompt_default_yn "Reuse existing secret [Y/n]:" y; then
                create_mysql_secret=false
            else
                create_mysql_secret=true
            fi
        else
            create_mysql_secret=true
        fi

        if $create_mysql_secret; then
            echo "Enter new billing database secret."
            MYSQL_ROOT_PASSWORD=''
            MYSQL_ROOT_PASSWORD_CONFIRMATION='nonempty'
            until [[ "$MYSQL_ROOT_PASSWORD" == "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]]; do
                read -sp "Billing database root password:" MYSQL_ROOT_PASSWORD
                echo
                read -sp "Confirm database root password:" MYSQL_ROOT_PASSWORD_CONFIRMATION
                echo
                if [[ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]]; then
                    log_bad "Passwords do not match."
                fi
            done
        else
            log "Using existing billing database secret."
        fi
    fi
fi

################################################################################

div
echo "COMPONENT: INSTALL"
echo "MMC.AI Manager:" $install_mmcai_manager
echo "MMC.AI Cluster:" $install_mmcai_cluster
echo "NVIDIA GPU Operator:" $install_nvidia_gpu_operator
echo "Kubeflow:" $install_kubeflow
echo "cert-manager:" $install_cert_manager

div
if prompt_default_yn "Confirm selection [y/N]:" n; then
    confirm_selection=true
else
    confirm_selection=false
fi

if ! $confirm_selection; then
    div
    log_good "Aborting..."
    exit 0
fi

div
log_good "Beginning setup..."

################################################################################

if $install_cert_manager; then
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-cert-manager.log"
    set_log_file $LOG_FILE
    div
    log_good "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install --wait --create-namespace -n cert-manager cert-manager jetstack/cert-manager --version $CERT_MANAGER_VERSION \
      --set crds.enabled=true \
      --debug
fi

if $install_kubeflow; then
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-kubeflow.log"
    set_log_file $LOG_FILE
    div
    log_good "Installing Kubeflow..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/playbooks/sysctl-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    build_kubeflow $TEMP_DIR

    log "Applying all Kubeflow resources..."
    while ! kubectl apply -f $TEMP_DIR/$KUBEFLOW_MANIFEST; do
        log "Kubeflow installation incomplete."
        log "Waiting 15 seconds before attempt..."
        sleep 15
    done
    log "Kubeflow installed."
fi

if $install_nvidia_gpu_operator; then
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-nvidia-gpu-operator.log"
    set_log_file $LOG_FILE
    div
    log_good "Installing NVIDIA GPU Operator..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update
    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/values/gpu-operator-values.yaml | \
    helm install --wait --create-namespace -n gpu-operator nvidia-gpu-operator nvidia/gpu-operator --version $NVIDIA_GPU_OPERATOR_VERSION -f - --debug
fi

if $install_mmcai_cluster; then
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-mmcai-cluster.log"
    set_log_file $LOG_FILE
    div
    log_good "Installing MMC.AI Cluster..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/playbooks/mysql-setup-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    # Create namespaces
    kubectl get namespace $RELEASE_NAMESPACE &>/dev/null || kubectl create namespace $RELEASE_NAMESPACE
    kubectl get namespace $MMCLOUD_OPERATOR_NAMESPACE &>/dev/null || kubectl create namespace $MMCLOUD_OPERATOR_NAMESPACE
    kubectl get namespace $PROMETHEUS_NAMESPACE &>/dev/null || kubectl create namespace $PROMETHEUS_NAMESPACE

    # Create MySQL secret
    if $create_mysql_secret; then
        kubectl delete secret -n $RELEASE_NAMESPACE mmai-mysql-secret --ignore-not-found

        # While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
        kubectl create secret generic -n $RELEASE_NAMESPACE mmai-mysql-secret \
            --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD
    fi

    helm install -n $RELEASE_NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster --version $MMAI_CLUSTER_VERSION \
        --set billing.database.nodeHostname=$MYSQL_NODE_HOSTNAME \
        --debug
fi

if $install_mmcai_manager; then
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-mmcai-manager.log"
    set_log_file $LOG_FILE
    div
    log_good "Installing MMC.AI Manager..."
    helm install -n $RELEASE_NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager --version $MMAI_MANAGER_VERSION --debug
fi
