
# Multi-Master Kubernetes Cluster Deployment Using KOPS

## Step-01: Introduction

In this section, we will create a highly available Kubernetes cluster using KOPS across three AWS Availability Zones.

### Cluster Configuration

| Component | Configuration |
|---|---|
| Cluster Name | rushilabs.in |
| AWS Region | us-east-1 |
| Availability Zones | us-east-1a, us-east-1b, us-east-1c |
| Control Plane Nodes | 3 |
| Worker Nodes | 3 |
| Total Nodes | 6 |
| Instance Type | t3.medium |
| Control Plane Volume | 10 GB |
| Worker Node Volume | 10 GB |
| Networking | Calico |
| State Store | s3://rushilabs.in |
| DNS | AWS Route 53 |

### Single-Master vs Multi-Master Cluster

| Component | Single Master | Multi Master |
|---|---|---|
| Control Plane Nodes | 1 | 3 |
| Worker Nodes | 3 | 3 |
| Total Nodes | 4 | 6 |
| Availability Zones | 1 | 3 |
| High Availability | No | Yes |
| etcd Quorum | 1 | 2 |
| Control Plane Failures Tolerated | 0 | 1 |

## Step-02: Configure Environment Variables

```bash
export CLUSTER_NAME=rushilabs.in
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
export NAME=rushilabs.in
export KOPS_STATE_STORE=s3://rushilabs.in
export KUBE_EDITOR=vi
```

Make sure the previous single-master cluster has been deleted before creating another cluster with the same name.

Wait at least 60 seconds after cluster deletion to avoid AWS SQS queue recreation errors.

## Step-03: Create Multi-Master Kubernetes Cluster

```bash
kops create cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --zones=us-east-1a,us-east-1b,us-east-1c \
  --node-count=3 \
  --control-plane-count=3 \
  --node-size=t3.medium \
  --control-plane-size=t3.medium \
  --control-plane-zones=us-east-1a,us-east-1b,us-east-1c \
  --control-plane-volume-size=10 \
  --node-volume-size=10 \
  --ssh-public-key=/root/.ssh/id_ed25519.pub \
  --networking=calico \
  --dns-zone=rushilabs.in \
  --yes
```

KOPS will provision the required AWS infrastructure and Kubernetes components.

### Availability Zone Distribution

| Availability Zone | Control Plane | Worker Node |
|---|---|---|
| us-east-1a | 1 | 1 |
| us-east-1b | 1 | 1 |
| us-east-1c | 1 | 1 |
| Total | 3 | 3 |

## Step-04: Configure Kubernetes Access

Export the Kubernetes configuration file.

```bash
kops export kubecfg \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --admin
```

Verify the Kubernetes context.

```bash
kubectl config current-context
```

Expected output:

```text
rushilabs.in
```

## Step-05: Validate Kubernetes Cluster

```bash
kops validate cluster --wait=20m
```

Check the Kubernetes nodes.

```bash
kubectl get nodes
```

Display detailed node information.

```bash
kubectl get nodes -o wide
```

Expected result:

- 3 control-plane nodes in Ready status.
- 3 worker nodes in Ready status.
- Total 6 Kubernetes nodes.

## Step-06: Verify Kubernetes Cluster Information

```bash
kubectl cluster-info
```

Expected output:

```text
Kubernetes control plane is running at https://api.rushilabs.in

CoreDNS is running at https://api.rushilabs.in/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Step-06.1: Verify Kubernetes Version

```bash
kubectl version
```

### Step-06.2: Verify Pods in Default Namespace

```bash
kubectl get pods
```

### Step-06.3: Verify Pods Across All Namespaces

```bash
kubectl get pods -A
```

### Step-06.4: Verify Kubernetes Namespaces

```bash
kubectl get namespaces
```

### Step-06.5: Verify Kubernetes System Components

```bash
kubectl get pods -n kube-system -o wide
```

## Step-07: Understanding KOPS Instance Groups

An instance group defines the configuration of Kubernetes nodes managed by KOPS.

Instance groups control:

- EC2 instance type.
- Minimum number of instances.
- Maximum number of instances.
- Availability Zone.
- Node role.
- Node configuration.

### Step-07.1: List Instance Groups

```bash
kops get ig
```

Expected output:

| NAME | ROLE | MACHINETYPE | MIN | MAX | ZONES |
|---|---|---|---|---|---|
| control-plane-us-east-1a | ControlPlane | t3.medium | 1 | 1 | us-east-1a |
| control-plane-us-east-1b | ControlPlane | t3.medium | 1 | 1 | us-east-1b |
| control-plane-us-east-1c | ControlPlane | t3.medium | 1 | 1 | us-east-1c |
| nodes-us-east-1a | Node | t3.medium | 1 | 1 | us-east-1a |
| nodes-us-east-1b | Node | t3.medium | 1 | 1 | us-east-1b |
| nodes-us-east-1c | Node | t3.medium | 1 | 1 | us-east-1c |

### Step-07.2: Edit Instance Group

```bash
kops edit instancegroup nodes-us-east-1a
```

Example configuration:

```yaml
spec:
  machineType: t3.medium
  minSize: 1
  maxSize: 1
```

To increase the number of worker nodes in us-east-1a, modify the minimum and maximum size.

```yaml
spec:
  machineType: t3.medium
  minSize: 2
  maxSize: 2
```

Save and exit the file.

### Step-07.3: Preview Cluster Changes

```bash
kops update cluster --name="${CLUSTER_NAME}"
```

### Step-07.4: Apply Cluster Changes

```bash
kops update cluster \
  --name="${CLUSTER_NAME}" \
  --yes \
  --admin
```

### Step-07.5: Verify KOPS Instances

```bash
kops get instances
```

### Step-07.6: Validate Updated Cluster

```bash
kops validate cluster --wait=20m
```

```bash
kubectl get nodes -o wide
```

After increasing the instance group size, the cluster should have 3 control-plane nodes and 4 worker nodes.

## Step-08: Understanding KOPS vs kubectl

| KOPS | kubectl |
|---|---|
| Creates Kubernetes clusters | Creates Kubernetes workloads |
| Manages cluster infrastructure | Manages Kubernetes resources |
| Manages instance groups | Manages Pods |
| Updates cluster configuration | Manages Deployments |
| Validates cluster infrastructure and health | Manages ReplicaSets |
| Deletes Kubernetes clusters | Manages Services |
| Manages cluster upgrades | Scales application workloads |

KOPS is primarily used for Kubernetes cluster lifecycle management.

kubectl is used to communicate with the Kubernetes API server and manage Kubernetes resources.

## Step-09: Understanding Control Plane Failure

### Question: If the control plane is down, will the application go down?

Not necessarily.

Applications generally run on worker nodes. If the control plane becomes unavailable, existing application containers can continue running on healthy worker nodes.

However, if the entire control plane becomes unavailable:

- New Pods cannot be scheduled.
- Deployment updates cannot be performed.
- Application scaling cannot be performed.
- Kubernetes API requests may fail.
- Failed Pods cannot be rescheduled to other nodes by the control plane.
- Cluster management operations are affected.

### Multi-Master High Availability

In a three-control-plane cluster:

- Total etcd members: 3
- Required quorum: 2
- Control-plane failures tolerated: 1

If one control-plane node fails, the remaining two can maintain etcd quorum.

If two control-plane nodes fail, etcd loses quorum and normal cluster management operations are affected.

## Step-10: Deploy a Sample Application Using Pod

We will use the following Docker Hub image:

```text
devopsbyrushi/rushi-app:1.0.0
```

### Step-10.1: Create a Pod

```bash
kubectl run pod \
  --image=devopsbyrushi/rushi-app:1.0.0
```

### Step-10.2: Verify Pod

```bash
kubectl get pods
```

Sample output:

```text
NAME   READY   STATUS    RESTARTS   AGE
pod    1/1     Running   0          36s
```

### Step-10.3: Display Detailed Pod Information

```bash
kubectl get pods -o wide
```

The wide output displays:

- Pod name.
- Pod status.
- Restart count.
- Pod IP address.
- Worker node name.

### Step-10.4: Describe Pod

```bash
kubectl describe pod pod
```

### Step-10.5: Check Pod Logs

```bash
kubectl logs pod
```

### Step-10.6: Delete Standalone Pod

```bash
kubectl delete pod pod
```

A standalone Pod is not automatically recreated after manual deletion.

## Step-11: Imperative vs Declarative Approach

Kubernetes resources can be created using two approaches.

| Imperative Approach | Declarative Approach |
|---|---|
| Uses kubectl commands | Uses YAML manifests |
| Quick resource creation | Defines desired resource configuration |
| Suitable for testing | Suitable for repeatable deployments |
| kubectl create | kubectl apply |

## Step-12: Create Deployment Using Imperative Approach

### Step-12.1: Perform Dry Run

```bash
kubectl create deployment rushiapp \
  --image=devopsbyrushi/rushi-app:1.0.0 \
  --replicas=4 \
  --dry-run=client
```

Expected output:

```text
deployment.apps/rushiapp created (dry run)
```

Dry run simulates resource creation without actually creating the Deployment.

### Step-12.2: Create Deployment

```bash
kubectl create deployment rushiapp \
  --image=devopsbyrushi/rushi-app:1.0.0 \
  --replicas=4
```

### Step-12.3: Verify Deployment

```bash
kubectl get deployments
```

Sample output:

```text
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
rushiapp   4/4     4            4           6s
```

### Step-12.4: Verify ReplicaSet

```bash
kubectl get replicasets
```

### Step-12.5: Verify Pods

```bash
kubectl get pods -o wide
```

Expected result:

- 4 application Pods.
- All Pods in Running status.
- Pods scheduled across available worker nodes.

Kubernetes does not guarantee one Pod per worker node unless appropriate scheduling constraints are configured.

### Step-12.6: Verify Deployment Rollout

```bash
kubectl rollout status deployment/rushiapp
```

## Step-13: Understanding Kubernetes Self-Healing

A Deployment manages a ReplicaSet, which maintains the desired number of Pods.

In our example, the desired replica count is 4.

### Step-13.1: List Application Pods

```bash
kubectl get pods -l app=rushiapp
```

### Step-13.2: Delete One Application Pod

Example:

```bash
kubectl delete pod rushiapp-7b9994f7f7-cfgsd
```

Replace the example Pod name with the actual Pod name from your cluster.

### Step-13.3: Verify Pod Recreation

```bash
kubectl get pods -o wide
```

Kubernetes automatically creates a replacement Pod to maintain the desired replica count of 4.

### Step-13.4: Monitor Pod Recreation

```bash
kubectl get pods -w
```

Press Ctrl+C to stop monitoring.

### Understanding Self-Healing

| Activity | Replica Count |
|---|---|
| Desired replicas | 4 |
| Running Pods before deletion | 4 |
| Running Pods immediately after deletion | May temporarily drop to 3 |
| Replacement Pods created | 1 |
| Final desired replicas | 4 |

## Step-14: Generate Deployment YAML Using Dry Run

```bash
kubectl create deployment rushiapp \
  --image=devopsbyrushi/rushi-app:1.0.0 \
  --replicas=4 \
  --dry-run=client \
  -o yaml > deployment.yaml
```

Verify the YAML file.

```bash
cat deployment.yaml
```

## Step-15: Create Deployment Using Declarative Approach

Delete the existing Deployment before demonstrating fresh creation using YAML.

```bash
kubectl delete deployment rushiapp
```

Create the Deployment using the YAML manifest.

```bash
kubectl apply -f deployment.yaml
```

Verify the Deployment.

```bash
kubectl get deployments
```

```bash
kubectl get replicasets
```

```bash
kubectl get pods -o wide
```

## Step-16: Delete Application Resources

Delete the Deployment.

```bash
kubectl delete deployment rushiapp
```

Verify application resource deletion.

```bash
kubectl get deployments
```

```bash
kubectl get replicasets
```

```bash
kubectl get pods
```

## Step-17: Delete Multi-Master Kubernetes Cluster

### Step-17.1: Configure Environment Variables

```bash
export CLUSTER_NAME=rushilabs.in
export KOPS_STATE_STORE=s3://rushilabs.in
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

### Step-17.2: Verify Existing Cluster

```bash
kops get clusters
```

### Step-17.3: Preview Cluster Deletion

```bash
kops delete cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

This command displays the AWS resources that will be deleted.

### Step-17.4: Delete Kubernetes Cluster

After reviewing the resources and confirming that the cluster is no longer required, execute:

```bash
kops delete cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --yes
```

### Step-17.5: Verify Cluster Deletion

```bash
kops get clusters
```

Confirm that rushilabs.in is no longer listed.

### Step-17.6: Wait Before Recreating Cluster

```bash
sleep 90
```

AWS SQS requires at least 60 seconds before recreating a recently deleted queue with the same name.

## Step-18: Important Notes

- KOPS manages the Kubernetes cluster lifecycle.
- kubectl manages Kubernetes application resources.
- Three control-plane nodes provide high availability.
- Three etcd members can tolerate one member failure.
- The Deployment controller maintains the desired replica count through its ReplicaSet.
- Always review AWS resources before cluster deletion.
- Verify that no unwanted EC2 instances, EBS volumes or load balancers remain after deletion.
- The manually created administration EC2 instance, IAM role, VPC, S3 state bucket, Route 53 hosted zone and GoDaddy domain are not intended to be deleted by this cluster deletion procedure.
- Stop or terminate unused AWS resources to avoid unnecessary billing.

## Author

**Rushi – Lead DevOps & Cloud Engineer**

RushiInfotech – DevOps & Cloud Technologies
