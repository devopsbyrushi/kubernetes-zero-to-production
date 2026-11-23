# **KOPS on AWS – Kubernetes Cluster Provisioning**

This module covers Kubernetes cluster provisioning using KOPS on AWS, starting from domain registration and AWS infrastructure setup to cluster creation, validation, troubleshooting, and deletion.

## **Module Structure**

```
02-KOPS-on-AWS/
├── 01-AWS-Prerequisites/
├── 02-Domain-Purchase-and-Route53/
├── 03-VPC-and-EC2-Setup/
├── 04-IAM-and-S3-Configuration/
├── 05-KOPS-and-kubectl-Installation/
├── 06-SSH-Key-and-DNS-Configuration/
├── 07-Kubernetes-Cluster-Creation/
├── 08-Cluster-Validation-and-Troubleshooting/
└── 09-Cluster-Deletion/
```

## **01. AWS Prerequisites**

Before starting, make sure you have:

- An active AWS account.
- Access to your GoDaddy account.
- A domain purchased from GoDaddy.
- Access to the AWS Management Console.
- An AWS region selected for the lab.
- Permissions to create VPC, EC2, IAM, S3, and Route 53 resources.

### **Lab Configuration**

| Component         | Value                   |
| ----------------- | ----------------------- |
| Domain            | `rushilabs.in`          |
| Domain registrar  | GoDaddy                 |
| AWS Region        | `us-east-1`             |
| Availability Zone | `us-east-1a`            |
| VPC CIDR          | `10.0.0.0/16`           |
| Subnet CIDR       | `10.0.1.0/24`           |
| EC2 Instance      | `t3.medium`             |
| Operating System  | Ubuntu Server 24.04 LTS |
| Security Group    | `kops-sg`               |
| S3 Bucket         | `rushilabs.in`          |
| Cluster Name      | `rushilabs.in`          |

## **02. Domain Purchase and Route 53 Configuration**

### **2.1 Purchase a Domain from GoDaddy**

1. Open [GoDaddy](https://www.godaddy.com/?utm_source=chatgpt.com).
2. Search for your required domain.
3. Purchase the domain.

For this lab, we are using:

```
rushilabs.in
```

4. Open the domain management page.
5. Navigate to DNS or Nameservers.
6. Keep the page open for the next configuration step.

### **2.2 What is Amazon Route 53?**

Amazon Route 53 is an AWS DNS service.

DNS stands for Domain Name System. It translates human-readable domain names into IP addresses.

For example:

```
rushilabs.in  →  IP Address
api.rushilabs.in → Kubernetes API Endpoint
```

**Why do we use Route 53 with KOPS?**

- To manage DNS records for the Kubernetes cluster.
- To configure the Kubernetes API endpoint.
- To connect the domain with AWS infrastructure.
- To manage DNS resolution for cluster-related services.

### **2.3 Create a Route 53 Hosted Zone**

1. Login to AWS Management Console.
2. Search for Route 53.
3. Navigate to **Hosted Zones**.
4. Click **Create hosted zone**.
5. Enter the domain name:

```
rushilabs.in
```

6\. Select:

```
Type: Public Hosted Zone
```

7\. Click Create hosted zone.

Route 53 will automatically create:

- One NS record.
- One SOA record.

### **2.4 Why Does Route 53 Provide Four Nameservers?**

After creating the hosted zone, Route 53 provides four authoritative nameservers.

These nameservers are responsible for answering DNS queries for your domain.

**Why four nameservers?**

- DNS availability.
- Fault tolerance.
- Redundancy.
- Reliable DNS resolution.

AWS distributes these nameservers across its DNS infrastructure to improve availability.

Example format:

```
ns-xxx.awsdns-xx.com
ns-xxx.awsdns-xx.net
ns-xxx.awsdns-xx.org
ns-xxx.awsdns-xx.co.uk
```

These are examples only. Always copy the actual four nameservers from your Route 53 hosted zone.

### **2.5 Configure Route 53 Nameservers in GoDaddy**

1. Login to GoDaddy.
2. Navigate to My Products.
3. Select your domain `rushilabs.in`.
4. Open DNS / Nameservers.
5. Select Change Nameservers.
6. Choose Custom Nameservers.
7. Copy all four nameservers from Route 53.
8. Paste them into GoDaddy.
9. Save the changes.

**How does this work?**

```
User Browser
     |
     v
rushilabs.in
     |
     v
GoDaddy Domain Registrar
     |
     v
Route 53 Nameservers
     |
     v
AWS DNS Records
     |
     v
Kubernetes API / AWS Resources
```

GoDaddy continues to manage the domain registration, while Route 53 manages DNS records for the domain.

### **2.6 Verify Nameserver Configuration**

Install DNS utilities:

```
sudo apt-get update
sudo apt-get install -y dnsutils
```

Verify:

```
dig NS rushilabs.in
```

The output should display the four Route 53 nameservers.

**Important:** DNS delegation may take time to propagate. Creating a hosted zone alone does not complete the integration. You must update the nameservers in GoDaddy.

## **03. VPC and EC2 Setup**

### **3.1 What is a VPC?**

VPC stands for Virtual Private Cloud.

Amazon VPC provides a logically isolated network in AWS where we can launch AWS resources.

Using a VPC, we can configure:

- IP address ranges.
- Subnets.
- Route tables.
- Internet Gateways.
- Network security.

For this KOPS lab, we will create one VPC and one subnet.

### **3.2 Create a VPC**

1. Login to AWS Console.
2. Search for VPC.
3. Navigate to Your VPCs.
4. Click Create VPC.
5. Select VPC Only.

Provide the following details:

| Setting   | Value         |
| --------- | ------------- |
| Name      | `kops-vpc`    |
| IPv4 CIDR | `10.0.0.0/16` |
| IPv6 CIDR | No IPv6 CIDR  |
| Tenancy   | Default       |

Click Create VPC.

### **3.3 Create a Subnet**

1. Navigate to VPC → Subnets.
2. Click Create Subnet.
3. Select `kops-vpc`.

Provide:

| Setting           | Value         |
| ----------------- | ------------- |
| Subnet Name       | `kops-subnet` |
| Availability Zone | `us-east-1a`  |
| IPv4 CIDR         | `10.0.1.0/24` |

Click Create Subnet.

### **3.4 Create an Internet Gateway**

An Internet Gateway allows resources in a public subnet to communicate with the internet when routing and public IP configuration are correctly configured.

1. Navigate to VPC → Internet Gateways.
2. Click Create Internet Gateway.
3. Enter:

```
Name: kops-igw
```

4. Create the Internet Gateway.
5. Select the Internet Gateway.
6. Choose Actions → Attach to VPC.
7. Select `kops-vpc`.

### **3.5 Configure Route Table**

1. Navigate to VPC → Route Tables.
2. Select the route table associated with `kops-subnet`.
3. Open Routes.
4. Click Edit Routes.
5. Add the following route:

| Destination | Target     |
| ----------- | ---------- |
| `0.0.0.0/0` | `kops-igw` |

6\. Save changes.

Enable auto-assign public IPv4 address for the subnet or enable public IP assignment when launching the EC2 instance.

### **3.6 Create a Security Group**

Navigate to:

```
EC2 → Security Groups → Create Security Group
```

Provide:

```
Security Group Name: kops-sg
Description: kops-sg
VPC: kops-vpc
```

Add inbound rule:

| Type | Port | Source               |
| ---- | ---- | -------------------- |
| SSH  | 22   | Your public IP `/32` |

Keep outbound rules configured for required AWS API and internet access.

**Security Note:** Avoid exposing SSH to `0.0.0.0/0` unless temporarily required for a lab. Restrict SSH access to your IP address.

### **3.7 Launch an EC2 Instance**

1. Navigate to EC2 → Instances.
2. Click Launch Instance.
3. Enter instance name:

```
kops-admin
```

4. Select Ubuntu Server 24.04 LTS.
5. Select instance type:

```
t3.medium
```

6. Select or create a key pair.
7. Under Network Settings, configure:

```
VPC: kops-vpc
Subnet: kops-subnet
Auto-assign Public IP: Enable
Security Group: kops-sg
```

8. Configure storage.
9. Launch the instance.

### **3.8 Connect to EC2**

```
ssh -i <key-file.pem> ubuntu@<EC2-PUBLIC-IP>
```

Update Ubuntu packages:

```
sudo apt-get update
sudo apt-get upgrade -y
```

Verify OS:

```
lsb_release -a
```

## **04. IAM and S3 Configuration**

### **4.1 Create an IAM Role**

KOPS requires AWS permissions to create and manage infrastructure.

For this lab, we will create an IAM role and attach it to the EC2 administration server.

Steps:

1. Open IAM.
2. Navigate to Roles.
3. Click Create Role.
4. Select AWS Service.
5. Select EC2 as the use case.
6. Attach the permissions required for the KOPS lab.

The original lab uses Administrator Access for practice. For production environments, use a least-privilege IAM policy.

7\. Enter role name:

```
kops-admin-role
```

8\. Create the role.

### **4.2 Attach IAM Role to EC2**

1. Navigate to EC2 → Instances.
2. Select `kops-admin`.
3. Choose Actions.
4. Select Security → Modify IAM Role.
5. Select `kops-admin-role`.
6. Update IAM role.

Verify the identity:

```
aws sts get-caller-identity
```

The output should show the attached IAM role.

### **4.3 Create an S3 Bucket**

KOPS uses an S3 bucket to store Kubernetes cluster configuration and state.

For this lab, we are using the domain name as the bucket name.

```
rushilabs.in
```

Create bucket:

```
aws s3api create-bucket \
  --bucket rushilabs.in \
  --region us-east-1
```

Enable versioning:

```
aws s3api put-bucket-versioning \
  --bucket rushilabs.in \
  --versioning-configuration Status=Enabled
```

Verify:

```
aws s3api get-bucket-versioning \
  --bucket rushilabs.in
```

Check bucket:

```
aws s3 ls s3://rushilabs.in
```

Configure KOPS state store:

```
export KOPS_STATE_STORE=s3://rushilabs.in
```

## **05. KOPS and kubectl Installation**

### **5.1 Install KOPS**

Connect to the Ubuntu administration EC2 instance.

Download KOPS:

```
curl -Lo kops https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
```

Make executable:

```
chmod +x kops
```

Move binary:

```
sudo mv kops /usr/local/bin/kops
```

Verify:

```
kops version
```

### **5.2 Install kubectl**

Update Ubuntu:

```
sudo apt-get update
sudo apt-get install -y curl
```

Download the latest stable release:

```
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
```

Download checksum:

```
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
```

Verify checksum:

```
echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
```

Expected output:

```
kubectl: OK
```

Install kubectl:

```
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Verify:

```
kubectl version --client
```

## **06. SSH Key and DNS Configuration**

### **6.1 Generate SSH Keys**

KOPS uses SSH public keys to configure access to Kubernetes instances.

Check existing keys:

```
ls -la ~/.ssh/
```

Generate an ED25519 key if required:

```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

Set permissions:

```
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

Verify:

```
cat ~/.ssh/id_ed25519.pub
```

Use the public key path in the KOPS cluster creation command.

For root:

```
/root/.ssh/id_ed25519.pub
```

For Ubuntu:

```
/home/ubuntu/.ssh/id_ed25519.pub
```

### **6.2 Configure Environment Variables**

Create a file:

```
sudo vim /home/ubuntu/ClusterCreation.sh
```

Add:

```
export CLUSTER_NAME=rushilabs.in
export NAME=rushilabs.in
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
export KOPS_STATE_STORE=s3://rushilabs.in
export KUBE_EDITOR=vim
```

Load variables:

```
source /home/ubuntu/ClusterCreation.sh
```

Verify:

```
echo "$CLUSTER_NAME"
echo "$AWS_REGION"
echo "$KOPS_STATE_STORE"
```

### **6.3 Create a DNS Test Record**

Before creating the Kubernetes cluster, verify DNS resolution.

Navigate to:

```
Route 53 → Hosted Zones → rushilabs.in
```

Click Create Record.

Provide:

| Setting     | Value         |
| ----------- | ------------- |
| Record Name | `demo`        |
| Record Type | A             |
| Value       | `10.20.30.40` |
| TTL         | Default       |

Save the record.

Here, `10.20.30.40` is only an example private IP used to test DNS resolution.

### **6.4 Test DNS from EC2**

Install DNS utilities:

```
sudo apt-get install -y dnsutils
```

Run:

```
nslookup demo.rushilabs.in
```

Example output:

```
Server:     127.0.0.53
Address:    127.0.0.53#53

Non-authoritative answer:
Name:       demo.rushilabs.in
Address:    10.20.30.40
```

Alternative:

```
dig demo.rushilabs.in
```

If DNS does not resolve, verify Route 53 records, GoDaddy nameservers, and DNS propagation.

## **07. Kubernetes Cluster Creation**

### **7.1 Cluster Configuration**

| Parameter            | Value                       |
| -------------------- | --------------------------- |
| Cluster Name         | `rushilabs.in`              |
| AWS Region           | `us-east-1`                 |
| Availability Zone    | `us-east-1a`                |
| KOPS State Store     | `s3://rushilabs.in`         |
| Control Plane Count  | 1                           |
| Worker Node Count    | 3                           |
| Instance Type        | `t3.medium`                 |
| Control Plane Volume | 10 GB                       |
| Worker Volume        | 10 GB                       |
| Networking           | Calico                      |
| SSH Public Key       | `/root/.ssh/id_ed25519.pub` |
| DNS Zone             | `rushilabs.in`              |

### **7.2 Create Kubernetes Cluster**

```
kops create cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --zones=us-east-1a \
  --node-count=3 \
  --control-plane-count=1 \
  --node-size=t3.medium \
  --control-plane-size=t3.medium \
  --control-plane-zones=us-east-1a \
  --control-plane-volume-size=10 \
  --node-volume-size=10 \
  --ssh-public-key=/root/.ssh/id_ed25519.pub \
  --networking=calico \
  --dns-zone=rushilabs.in \
  --yes
```

**Note:** The SSH public key path must match the Linux user running KOPS. Change it if you are running KOPS as `ubuntu` instead of `root`.

### **7.3 Verify KOPS Configuration**

```
kops get cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

Check instance groups:

```
kops get instancegroups \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

### **7.4 Apply Cluster Configuration**

Review the update plan:

```
kops update cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

Apply changes if required:

```
kops update cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --yes
```

### **7.5 Raft Consensus Algorithm**

Kubernetes uses etcd as its distributed key-value store.

etcd uses the Raft consensus algorithm to maintain consistency among its members.

For a three-member etcd cluster:

- A majority of members must be available.
- Three members can tolerate one member failure.
- If two members fail, quorum is lost.

**Important:** Our current lab configuration uses one control-plane node. A highly available Kubernetes control plane requires a separate design with multiple control-plane and etcd members, commonly three.

## **08. Cluster Validation and Troubleshooting**

### **8.1 Validate Cluster**

```
kops validate cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

Wait until the cluster becomes ready.

### **8.2 Export kubeconfig**

```
kops export kubecfg \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --admin
```

Protect the kubeconfig because it contains privileged cluster credentials.

### **8.3 Verify Kubernetes Cluster**

```
kubectl cluster-info
```

Check nodes:

```
kubectl get nodes -o wide
```

Check namespaces:

```
kubectl get namespaces
```

Check all pods:

```
kubectl get pods -A
```

### **Expected Lab Result**

The lab is configured with:

- 1 Control Plane Node
- 3 Worker Nodes

All nodes should eventually show:

```
STATUS: Ready
```

### **8.4 Check System Pods**

```
kubectl get pods -n kube-system
```

Describe a pod:

```
kubectl describe pod <pod-name> -n <namespace>
```

Check logs:

```
kubectl logs <pod-name> -n <namespace>
```

### **8.5 Common Troubleshooting**

**AWS Access Denied**

```
aws sts get-caller-identity
```

Check IAM role and permissions.

**S3 Bucket Not Found**

```
aws s3 ls s3://rushilabs.in
```

Check bucket name and state-store configuration.

**SSH Key Not Found**

```
ls -la ~/.ssh/
```

Verify the public key path.

**DNS Resolution Issue**

```
dig NS rushilabs.in
dig api.rushilabs.in
nslookup demo.rushilabs.in
```

Check GoDaddy nameservers and Route 53 records.

**Kubernetes API Not Reachable**

```
kubectl config current-context
kubectl cluster-info
```

Check kubeconfig, API DNS resolution, and network access.

**Node Not Ready**

```
kubectl get nodes -o wide
kubectl describe node <node-name>
kubectl get pods -n kube-system
```

Check EC2 instance status, networking, and Kubernetes system pods.

## **09. Cluster Deletion**

### **Important**

Cluster deletion is a destructive operation. Back up required data and confirm the target cluster before proceeding.

### **9.1 Verify Cluster**

```
kops get cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

### **9.2 Delete Cluster**

```
kops delete cluster \
  --name=rushilabs.in \
  --state=s3://rushilabs.in \
  --yes
```

### **9.3 Verify AWS Resources**

After deletion, check AWS for remaining resources:

- EC2 instances.
- EBS volumes.
- Load balancers.
- Elastic IP addresses.
- VPC and subnets.
- Internet Gateway.
- Route tables.
- Route 53 records.

The KOPS deletion command does not automatically mean the S3 bucket, Route 53 hosted zone, or GoDaddy domain registration is deleted. Review those separately.

## **Lab Completion Checklist**

- AWS account ready.
- Domain purchased from GoDaddy.
- Route 53 hosted zone created.
- Four Route 53 nameservers configured in GoDaddy.
- DNS delegation verified.
- VPC created.
- Subnet created.
- Internet Gateway configured.
- Route table configured.
- Security group created.
- Ubuntu 24.04 EC2 instance launched.
- IAM role created and attached to EC2.
- S3 bucket created.
- S3 versioning enabled.
- KOPS installed.
- kubectl installed.
- SSH key generated or verified.
- Environment variables configured.
- DNS test record created and verified.
- Kubernetes cluster created.
- Cluster validation completed.
- kubectl access verified.
- All nodes checked.
- System pods checked.

## **Quick Command Reference**

```
# Verify AWS identity
aws sts get-caller-identity

# Check KOPS version
kops version

# Check kubectl version
kubectl version --client

# Set KOPS state store
export KOPS_STATE_STORE=s3://rushilabs.in

# Verify DNS nameservers
dig NS rushilabs.in

# Test DNS record
nslookup demo.rushilabs.in

# List KOPS clusters
kops get clusters

# Validate Kubernetes cluster
kops validate cluster --name="${CLUSTER_NAME}"

# Export kubeconfig
kops export kubecfg --name="${CLUSTER_NAME}" --admin

# Check Kubernetes nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Delete cluster - destructive
kops delete cluster --name="${CLUSTER_NAME}" --yes
```

**End of Module: KOPS on AWS**
