#!/bin/bash

source ./logging.sh

mgmt_node=$(kubectl get nodes --no-headers -l node-role.kubernetes.io/control-plane=  | awk '{print $1}')
work_node=$(kubectl get nodes --no-headers -l node-role.kubernetes.io/control-plane!= | awk '{print $1}')

# Remove taint that prevents mgmt node from running workloads.
kubectl taint nodes $MGMT_NODE node-role.kubernetes.io/master:NoSchedule-

# Drain worker nodes.
for worker in $WORK_NODE; do
    kubectl drain $worker
done

wget -O mmcai_adjust_requests.py https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/refs/heads/main/mmcai_adjust_requests.py 

# Dependencies for the requests.py script
pip install kubernetes

python3 mmcai_adjust_requests.py

# Wait to allow pods to reschedule onto the managment node...
# This takes some time to stabilize.

div
log "Waiting for evicted pods to stabilize for 120 seconds..."
sleep 3

timeout 120 kubectl get pods -A --watch

div
log "Finish waiting. Uncordoning worker nodes..."

# Allow pods to be scheduled on the GPU node again
## TODO: add schedulable taint to the worker nodes. ##
for worker in $WORK_NODE; do
    kubectl uncordon $worker
done
