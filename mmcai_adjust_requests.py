from kubernetes import client, config
from kubernetes.client.rest import ApiException
import sys
import datetime

# Load the kubeconfig
config.load_kube_config()

# Initialize API clients
v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()

def get_pods_with_high_cpu_requests(threshold=0.1):
    # List all pods in all namespaces
    all_pods = v1.list_pod_for_all_namespaces(watch=False)
    pod_list = []

    # Filter pods with CPU requests higher than the threshold
    for pod in all_pods.items:
        for container in pod.spec.containers:
            # If limits are present, use them as a baseline;
            # otherwise fall back to requests
            limits = container.resources.limits
            requests = container.resources.requests
            if limits and 'cpu' in limits:
                # Don't use requests if the limits have 'cpu'
                requests = limits
            if requests is None or 'cpu' not in requests:
                # Skip this container if no 'cpu' in requests
                continue
            # Else, modify the requests, either by reducing
            # w.r.t. the limit or w.r.t. the old request value
            cpu_request = requests['cpu']
            # Convert the CPU request into millicores for comparison
            cpu_request_m = convert_cpu_to_millicores(cpu_request)
            if cpu_request_m >= 100:  # Example: threshold = 100m
                pod_list.append({
                    'namespace': pod.metadata.namespace,
                    'name': pod.metadata.name,
                    'labels': pod.metadata.labels,
                    'cpu_request': cpu_request_m,
                    'container': container.name,  # Add a comma here
                    'owner': pod.metadata.owner_references[0]
                })

    # Sort pods by CPU requests, highest first
    pod_list.sort(key=lambda x: x['cpu_request'], reverse=True)
    return pod_list

def convert_cpu_to_millicores(cpu):
    """ Convert CPU request into millicores. """
    if 'm' in cpu:
        return int(cpu.replace('m', ''))
    else:
        return int(float(cpu) * 1000)

def suggest_cpu_request_reduction(pod):
    """ Suggest halving the CPU request for the pod """
    new_cpu_millicores = 50 # max(pod['cpu_request'] // 10, 20) # Do not reduce below 20m
    return new_cpu_millicores

def make_cpu_requests(deployment, namespace, container_name, new_cpu_request):
    """ Redue the CPU requests for the container in the deployment. """
    try:
        # Get the deployment
        deployment_object = apps_v1.read_namespaced_deployment(deployment, namespace)

        # Find the container and update its CPU request
        for container in deployment_object.spec.template.spec.containers:
            if container.name == container_name:
                container.resources.requests['cpu'] = new_cpu_request
                print(f"Updated {container_name} in {deployment} (namespace: {namespace}) to {new_cpu_request}")

        # Apply the changes
        apps_v1.replace_namespaced_deployment(deployment, namespace, deployment_object)

    except ApiException as e:
        print(f"Exception when updating deployment: {e}", file=sys.stderr)

def restart_pod(pod_name, namespace):
    """ Restart a pod by deleting it and letting Kubernetes recreate it """
    try:
        print(f"Restarting pod {pod_name} in namespace {namespace}...")
        v1.delete_namespaced_pod(name=pod_name, namespace=namespace)
    except ApiException as e:
        print(f"Exception when restarting pod: {e}", file=sys.stderr)

def restart_replicaset(set_name, namespace):
    """ Restart a replicaset by deleting it and letting Kubernetes recreate it """
    try:
        print(f"Restarting ReplicaSet {set_name} in namespace {namespace}...")
        v1.delete_namespaced_pod(name=set_name, namespace=namespace)
    except ApiException as e:
        print(f"Exception when restarting pod: {e}", file=sys.stderr)

def restart_deployment(v1_apps, deployment, namespace):
    now = datetime.datetime.utcnow()
    now = str(now.isoformat("T") + "Z")
    body = {
        'spec': {
            'template':{
                'metadata': {
                    'annotations': {
                        'kubectl.kubernetes.io/restartedAt': now
                    }
                }
            }
        }
    }
    try:
        v1_apps.patch_namespaced_deployment(deployment, namespace, body, pretty='true')
    except ApiException as e:
        print("Exception when calling AppsV1Api->read_namespaced_deployment_status: %s\n" % e)

def main():
    # Get pods with the highest CPU requests (now with a lower threshold)
    high_cpu_pods = get_pods_with_high_cpu_requests()

    # List the pods with high CPU requests and suggested changes
    modified_pods = []
    print("The following pods have high CPU requests and need changes:")
    for pod in high_cpu_pods:
        suggested_cpu_request = suggest_cpu_request_reduction(pod)

        # Ignore pods with labels that we care about
        if 'mmc.ai/project' in pod['labels']:
            print(f"Pod: {pod['name']} (Namespace: {pod['namespace']}, Container: {pod['container']})")
            print(f"Is managed by MMC.AI. Will not adjust CPU Request.")
            print("-" * 40)
            continue

        # Only list pods where the suggested CPU request is different from the current CPU request
        if pod['cpu_request'] != suggested_cpu_request:
            print(f"Pod: {pod['name']} (Namespace: {pod['namespace']}, Container: {pod['container']})")
            print(f"Current CPU Request: {pod['cpu_request']}m")
            print(f"Suggested new CPU Request: {suggested_cpu_request}m")
            print("-" * 40)
            modified_pods.append(pod)

    # If no changes are needed, exit
    if not modified_pods:
        print("No pods require changes. Exiting.")
        sys.exit(0)

    # Prompt user to confirm changes, default to No
    confirm = input("Do you want to apply these changes? (Y/N) [default: N]: ").strip().lower()

    if confirm != 'y':
        print("No changes were made. Exiting.")
        sys.exit(0)

    # For each pod with high CPU request, find its deployment and apply the modified CPU request
    for pod in modified_pods:
        print(f"Processing pod {pod['name']} in namespace {pod['namespace']}")

        # Identify the deployment controlling this pod
        pod_metadata = v1.read_namespaced_pod(pod['name'], pod['namespace'])
        owner_references = pod_metadata.metadata.owner_references

        for owner in owner_references:
            if owner.kind == "ReplicaSet":
                # Find the deployment controlling the ReplicaSet
                replica_set = apps_v1.read_namespaced_replica_set(owner.name, pod['namespace'])
                deployment_owner = replica_set.metadata.owner_references[0]

                if deployment_owner.kind == "Deployment":
                    # Save the deployment owner name for a later rollout
                    pod['deployment'] = deployment_owner.name
                    # Halve the CPU request in the container for the controlling deployment
                    new_cpu_request = f"{suggest_cpu_request_reduction(pod)}m"
                    make_cpu_requests(deployment_owner.name, pod['namespace'], pod['container'], new_cpu_request)

    # Restart the modified pods to apply the changes
    for pod in modified_pods:
        if 'deployment' in pod:
            restart_deployment(apps_v1, pod['deployment'], pod['namespace'])
        else:
            restart_pod(pod['name'], pod['namespace'])

    # Wait a few seconds for the pods to restart
    import time
    print("Waiting for pods to restart...")
    time.sleep(5)

    # Verify the changes by listing the updated CPU requests for the modified pods
    print("\nUpdated list of pods and their CPU requests:")
    updated_pods = get_pods_with_high_cpu_requests()
    for pod in updated_pods:
        print(f"Pod: {pod['name']} (Namespace: {pod['namespace']}, Container: {pod['container']})")
        print(f"Updated CPU Request: {pod['cpu_request']}m")
        print("-" * 40)

if __name__ == '__main__':
    main()
