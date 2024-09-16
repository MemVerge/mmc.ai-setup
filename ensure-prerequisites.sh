#!/bin/bash

set -euo pipefail

imports='
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

OS=windows
if [[ "$OSTYPE" == linux* ]]; then
  OS=linux
elif [[ "$OSTYPE" == darwin* ]]; then
  OS=darwin
fi
echo "Operating system: $OS"

if [[ "$OS" == windows ]]; then
    log_bad "OS not supported. Please install prerequisites manually."
    exit 1
fi

ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64";;
    x86|i686|i386) ARCH="386";;
    aarch64) ARCH="arm64";;
esac
echo "Architecture: $ARCH"

INSTALL_DIR="/usr/local/bin"

div
if ! cvenv mmai-test-venv; then
    rvenv mmai-test-venv || true
    log_bad "venv creation failed. Please fix before continuing."
    exit 1
else
    rvenv mmai-test-venv
    log "venv creation works."
fi

div
if ! which kubectl; then
    log_good "Installing kubectl..."
    KUBECTL_VERSION="$(curl -Lfs https://dl.k8s.io/release/stable.txt)"
    sudo curl -Lfo $INSTALL_DIR/kubectl "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$OS/$ARCH/kubectl"
    sudo chmod +x /usr/local/bin/kubectl
    echo "kubectl installed to $INSTALL_DIR/kubectl"
else
    log "Found kubectl."
fi

div
if ! which kustomize; then
    log_good "Installing Kustomize..."
    curl -Lf "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | sudo bash -s -- $INSTALL_DIR
else
    log "Found Kustomize."
fi

div
if ! which helm; then
    log_good "Installing Helm..."
    curl -Lf "https://raw.githubusercontent.com/helm/helm/unified-setup/scripts/get-helm-3" | bash
else
    log "Found Helm."
fi

div
if ! which jq; then
    log_good "Installing jq..."
    JQ_VERSION="1.7.1"

    JQ_OS=$OS
    if [[ "$JQ_OS" == "darwin" ]]; then
      JQ_OS=macos
    fi

    JQ_ARCH=$ARCH
    if [[ "$JQ_ARCH" == "386" ]]; then
      JQ_ARCH="i386"
    fi

    sudo curl -Lfo $INSTALL_DIR/jq "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-$JQ_OS-$JQ_ARCH"
    sudo chmod +x /usr/local/bin/jq
    echo "jq installed to $INSTALL_DIR/jq"
else
    log "Found jq."
fi

div
if ! which yq; then
    log_good "Installing yq..."
    YQ_VERSION="v4.44.3"

    sudo curl -Lfo $INSTALL_DIR/yq "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_$OS_$ARCH"
    sudo chmod +x /usr/local/bin/yq
    echo "yq installed to $INSTALL_DIR/yq"
else
    log "Found yq."
fi
