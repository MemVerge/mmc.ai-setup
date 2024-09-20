# Memory Machine AI Setup Guide

## Setting up user accounts for Ansible

A user with `sudo` permissions is needed on each host where Kubernetes will be installed.

Log into each target host as `root`. Then, execute the following commands:

```bash
# 'mmai-admin' can be any username.
# Fill out name and password prompts as needed.
sudo adduser mmai-admin

# Adds the new user to the sudoers group.
sudo usermod -aG sudo mmai-admin

# Allows the new user to execute 'sudo <cmd>' without prompting for a password.
echo "mmai-admin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/mmai-admin
```

## Enabling private-key SSH

To allow Ansible to connect to remote hosts without querying for a password, private-key SSH connections must be enabled. From the provisioning machine, follow these steps:
```bash
# Generate a public/private keypair for the current user;
# Can leave all fields empty.
ssh-keygen

# Substitute <username> with the name of a user account on server <host>;
# provide the requisite password. If the steps above were followed, then
# <username> will be 'mmai-admin'.
ssh-copy-id <username>@<host>
```

These instructions come from [NVIDIA’s guide on Ansible](https://github.com/NVIDIA/deepops/blob/master/docs/deepops/ansible.md#passwordless-configuration-using-ssh-keys), which contains more information.

## [OPTIONAL] Installing Kubernetes via DeepOps

The following set of commands will install Ansible on the provisioning machine. They must be run as a regular user.
```bash
git clone https://github.com/NVIDIA/deepops.git
cd deepops
git checkout 23.08
./scripts/setup.sh
```

### Ansible configuration

Once Ansible installation is complete, `deepops/config/inventory` must be configured by the system admin.
This file defines which hosts will be used for Kubernetes installation.

Within, there are four relevant host groups:

- **`[all]`**
  A list of the hosts that will participate in the Kubernetes cluster.
  For example:
  ```
    [all]
    <host-1-name>   ansible_host=<host-1-ip-address>
    <host-2-name>   ansible_host=<host-2-ip-address>
    # The following will configure the local machine as a target:
    # host-1        ansible_host=localhost
  ```
  In order to have the Kubernetes node names match with the names of the servers in the cluster, it is best to let `<host-N-name>` be the domain name of the remote host. You can determine a host's domain by running the `hostname` command (without the optional `-f` flag, which prints the fully qualified domain name) on each machine.
- **`[kube-master]`**
  The `<host-name>` of the node in the cluster where Kubernetes' control plane will run. This is most likely the provisioning machine.
- **`[etcd]`**
  Holds the node, or nodes, that will host Kubernetes' `etcd` key-value store. This is also, most likely, the provisioning machine.
- **`[kube-node]`**
  Should contain the cluster's "worker nodes" -- that is, nodes that do not appear in `[kube-master]`, but are expected to run workloads.

### Kubernetes installation script

Once Ansible configuration is complete, copy these commands into your terminal to install Kubernetes:
```bash
git clone https://github.com/MemVerge/mmc.ai-setup
cd mmc.ai-setup
./deepops-setup.sh
```

## Installing Memory Machine AI

> **Important:**
> The following prerequisites are necessary if you did not follow the instructions above:
> 1. User accounts for Ansible set up.
> 2. Private-key SSH enabled.
> 3. Kubernetes cluster set up.
> 4. [Default StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/#default-storageclass) in Kubernetes cluster set up.

### [INTERNAL] Helm login secrets

In order to download the pre-release packages, MemVerge team members must authenticate with the Github container registry.

First, create a personal access token on this Github page: https://github.com/settings/tokens

Ctrl-f to find `read:packages` and select the checkbox.

Then press "**Generate token**."

Copy the token that is highlighted in green. Save it to your local machine if you do not want to create a new token during reinstallation.

Then run the following command:

``` bash
helm registry login ghcr.io/memverge/charts
# Username: <github-username>
# Password: <personal-access-token>
```

### Image pull secrets

Copy the `mmcai-ghcr-secret.yaml` file provided by MemVerge to the node with `kubectl` access (i.e., the "control plane node"). Then, deploy its image pull credentials to the cluster like so:
```bash
kubectl apply -f mmcai-ghcr-secret.yaml
```

### Ansible configuration

In an inventory file (which can be named anything), configure two host groups:
- **`[all]`**
  > **Note:**
  > The [all] group in this section should be identical to the one in `deepops/config/inventory` if you installed Kubernetes via DeepOps.

  A list of the hosts that will participate in the Kubernetes cluster.
  For example:
  ```
  [all]
  <host-1-name>   ansible_host=<host-1-ip-address>
  <host-2-name>   ansible_host=<host-2-ip-address>
  # The following will configure the local machine as a target:
  # host-1        ansible_host=localhost
  ```
  In order to have the Kubernetes node names match with the names of the servers in the cluster, it is best to let `<host-N-name>` be the domain name of the remote host. You can determine a host's domain by running the `hostname` command (without the optional `-f` flag, which prints the fully qualified domain name) on each machine.
- **`[mmai_database]`**
  Memory Machine AI MySQL database (single) node. The specified node will be used for a database.
  For example:
  ```
  [mmai_database]
  <host-name>     ansible_host=<host-ip-address>
  ```

This file will be used by the Memory Machine AI installation script.

### Memory Machine AI installation script

Download and run the interactive `mmcai-setup.sh` script on the control plane node.

You will have a chance to confirm your changes after making your selections:

```bash
git clone https://github.com/MemVerge/mmc.ai-setup
cd mmc.ai-setup
./mmcai-setup.sh
```

If MMC.AI Manager is installed, the MMC.AI dashboard should be accessible at `http://<control-plane-ip>:32323`.

If Kubeflow is installed, the following command should print the port for the Kubeflow Central Dashboard:

```bash
echo $(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
```

Using this port, the URL `http://<node-ip>:<port>` will fetch the Kubeflow Central Dashboard, where `<node-ip>` is the IPv4 address of any node on the cluster.

# Memory Machine AI Teardown Guide

## Uninstalling Memory Machine AI

### Ansible configuration

In an inventory file (which can be named anything), configure the host group:
- **`[mmai_database]`**
  Memory Machine AI MySQL database (single or multiple) nodes. Databases on the specified nodes will be removed.
  For example:
  ```
  [mmai_database]
  <host-1-name>   ansible_host=<host-1-ip-address>
  <host-2-name>   ansible_host=<host-2-ip-address>
  ```

This file will be used by the Memory Machine AI uninstallation script.

### Memory Machine AI uninstallation script

Download and run the interactive `mmcai-teardown.sh` script on the control plane node.

Some teardown operations are dangerous and may cause data loss or other installations in the cluster to malfunction, if they rely on the same resources.
If you have nothing else installed in the cluster and want to remove everything, answer 'y' to each prompt.

You will have a chance to confirm your changes after making your selections:
```bash
git clone https://github.com/MemVerge/mmc.ai-setup
cd mmc.ai-setup
./mmcai-teardown.sh
```
