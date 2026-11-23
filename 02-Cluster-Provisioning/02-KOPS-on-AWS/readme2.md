
# KOPS on AWS – Kubernetes Cluster Provisioning

This module covers Kubernetes cluster provisioning using KOPS on AWS, starting from domain registration and AWS infrastructure setup to cluster creation, validation, troubleshooting, and deletion.

| Field | Description |
|---|---|
| **Title** | KOPS on AWS – Kubernetes Cluster Provisioning |
| **Description** | Learn to provision, validate, and manage a Kubernetes cluster on AWS using KOPS. |

---

## Module Structure

```text
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

---

## Step-01: Introduction

- Provision a Kubernetes cluster on AWS using KOPS.
- Configure DNS using GoDaddy and Amazon Route 53.
- Create the required AWS networking, IAM, and S3 resources.
- Install KOPS and kubectl.
- Create and validate the Kubernetes cluster.
- Understand cluster troubleshooting and deletion.

---

## Step-02: AWS Prerequisites

Before starting, make sure you have:

- An active AWS account.
- Access to the GoDaddy account where the domain will be purchased.
- An AWS region selected for the lab.
- Permissions to create VPC, EC2, IAM, S3, and Route 53 resources.
- An Ubuntu administration machine or the ability to create one during this lab.

### Step-02.1: Lab Configuration

| Component | Lab Value |
|---|---|
| Domain | `rushilabs.in` |
| Domain Registrar | GoDaddy |
| AWS Region | `us-east-1` |
| Availability Zone | `us-east-1a` |
| VPC CIDR | `10.0.0.0/16` |
| Subnet CIDR | `10.0.1.0/24` |
| Administration Instance | `t3.medium` |
| Operating System | Ubuntu Server 24.04 LTS |
| Security Group | `kops-sg` |
| KOPS State Bucket | `rushilabs.in` |
| Cluster Name | `rushilabs.in` |

> **Note:** Use the CIDR values above as example lab network values. If your AWS account already has overlapping networks, select non-overlapping CIDR ranges.

---

## Step-03: Domain Purchase and Route 53 Configuration

### Step-03.1: Purchase a Domain from GoDaddy

1. Sign in to [GoDaddy](https://www.godaddy.com/).
2. Search for the required domain.
3. Purchase the domain.

   ```text
   rushilabs.in
   ```

4. Open the domain's DNS or nameserver management page.
5. Keep the GoDaddy domain management page available. You will update its nameservers after creating the Route 53 hosted zone.

A domain registrar is the company through which the domain is registered. GoDaddy manages the domain registration in this lab.

### Step-03.2: What is Amazon Route 53?

Amazon Route 53 is AWS's scalable DNS (Domain Name System) service.

DNS translates human-readable domain names, such as `rushilabs.in`, into IP addresses or other DNS targets.

For this KOPS lab, Route 53 is used to:

- Host the DNS zone.
- Manage DNS records.
- Configure DNS records required for the Kubernetes cluster.
- Manage the Kubernetes API endpoint DNS.

### Step-03.3: Create a Route 53 Hosted Zone

1. Sign in to the AWS Management Console.
2. Open **Route 53**.
3. Select **Hosted zones**.
4. Choose **Create hosted zone**.
5. Enter the domain:

   ```text
   rushilabs.in
   ```

6. Select **Public hosted zone**.
7. Create the hosted zone.

Route 53 creates the hosted zone and displays its DNS record sets.

You will see:

- NS record
- SOA record

The NS record contains four AWS nameservers.

### Step-03.4: Why Are There Four Route 53 Nameservers?

A public hosted zone is assigned four authoritative nameservers.

They provide DNS availability and resilience.

These are the nameservers that must be configured at the domain registrar so that DNS queries for the domain are delegated to Route 53.

The four nameservers are unique to the hosted zone.

Copy the exact four values displayed in your Route 53 NS record.

Example format only:

```text
ns-xxx.awsdns-xx.com
ns-xxx.awsdns-xx.net
ns-xxx.awsdns-xx.org
ns-xxx.awsdns-xx.co.uk
```

Do not use nameservers copied from another hosted zone or from an example.

### Step-03.5: Update Nameservers in GoDaddy

**GoDaddy Navigation:**

```text
My Products
    → Domains
        → rushilabs.in
            → DNS / Nameservers
                → Change Nameservers
                    → Custom Nameservers
```

1. Copy all four nameservers from the Route 53 hosted zone's NS record.
2. Paste all four values into the custom nameserver fields in GoDaddy.
3. Save the changes.

This connects the domain registered at GoDaddy to the DNS hosted zone in AWS Route 53.

DNS delegation may take time to propagate.

### Step-03.6: Verify Nameserver Delegation

Install DNS utilities on your Linux machine if required:

```bash
sudo apt-get update
sudo apt-get install -y dnsutils
```

Verify the nameservers:

```bash
dig NS rushilabs.in
```

The returned nameservers should match the four nameservers assigned by Route 53.

> **Important:** Creating a Route 53 hosted zone alone does not redirect the domain's DNS to AWS. The registrar's nameserver settings must point to the four Route 53 nameservers.

---

## Step-04: VPC and EC2 Setup

### Step-04.1: What is a VPC?

Amazon Virtual Private Cloud (VPC) provides a logically isolated network in AWS.

You define the network IP range, subnets, routing, and network security for the AWS resources deployed inside it.

For this lab, create a dedicated VPC and one subnet, then deploy the KOPS administration EC2 instance in that subnet.

### Step-04.2: Create a VPC Using the VPC and More Option

For this lab, use the AWS **VPC and more** wizard.

It creates the VPC and supporting network components together, so you do not need to create the Internet Gateway and route table manually.

1. Open the AWS Management Console.
2. Navigate to **VPC → Your VPCs**.
3. Choose **Create VPC**.
4. Under **Resources to create**, select **VPC and more**.
5. Configure the settings:

| Setting | Value |
|---|---|
| Name Tag Auto-generation | `kops` |
| IPv4 CIDR Block | `10.0.0.0/16` |
| Number of Availability Zones | `1` |
| Availability Zone | `us-east-1a` |
| Number of Public Subnets | `1` |
| Number of Private Subnets | `0` |
| NAT Gateways | `None` |
| VPC Endpoints | `None` |

6. Review the resource preview.
7. Confirm that one public subnet and an Internet Gateway are included.
8. Choose **Create VPC**.

The wizard creates the VPC and selected networking resources, including:

- Public subnet
- Internet Gateway
- Route table
- Default route to the Internet Gateway

### Step-04.3: Understand the VPC Components

| Component | Purpose in This Lab |
|---|---|
| VPC | Provides an isolated AWS network with CIDR `10.0.0.0/16` |
| Public Subnet | Hosts the KOPS administration EC2 instance |
| Internet Gateway (IGW) | Enables internet connectivity for resources with public IP addresses |
| Route Table | Directs internet-bound traffic (`0.0.0.0/0`) to the Internet Gateway |
| Security Group | Controls inbound and outbound traffic for the EC2 instance |

**Why use a public subnet?**

The administration EC2 instance needs internet access to:

- Download KOPS.
- Download kubectl.
- Install Linux packages.
- Communicate with AWS services.

In this lab, a public subnet with an Internet Gateway and a public IPv4 address provides that connectivity.

### Step-04.4: Verify the VPC Networking

After the wizard completes:

1. Open **VPC → Your VPCs** and confirm that the VPC was created.
2. Open **VPC → Subnets** and confirm that the public subnet exists in `us-east-1a`.
3. Open **VPC → Internet Gateways** and confirm that an Internet Gateway is attached to the new VPC.
4. Open **VPC → Route Tables** and check that the public subnet is associated with a route table containing:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | `local` |
| `0.0.0.0/0` | Internet Gateway |

5. Confirm that the public subnet has **Auto-assign public IPv4 address** enabled.

If it is disabled, enable it in the subnet settings or enable public IP assignment when launching the EC2 instance.

> **Note:** The VPC and more wizard creates these resources for you. The verification steps help you understand what was created and confirm that the subnet has internet routing.

### Step-04.5: Create a Security Group

Create a security group for the KOPS administration server.

1. Navigate to **EC2 → Security Groups**.
2. Choose **Create security group**.
3. Enter:

```text
Security Group Name: kops-sg
Description: kops-sg
VPC: kops-vpc
```

4. Add the required inbound rule for SSH:

| Type | Port | Source |
|---|---:|---|
| SSH | 22 | Your public IP address `/32` |

5. Keep outbound access as required for package downloads and AWS API communication.
6. Create the security group.

> **Security Note:** The original lab setup uses SSH source `0.0.0.0/0` (Anywhere). This exposes SSH to the entire internet. Prefer **My IP** or a trusted corporate IP range. If you temporarily use `0.0.0.0/0` for a lab, restrict it immediately after connectivity testing.

### Step-04.6: Launch the KOPS Administration EC2 Instance

1. Open **EC2 → Instances → Launch instances**.
2. Enter an instance name:

   ```text
   kops-admin
   ```

3. Select **Ubuntu Server 24.04 LTS**.
4. Select instance type:

   ```text
   t3.medium
   ```

5. Select or create a key pair and securely save the private key.
6. Under **Network settings**, configure:

| Setting | Value |
|---|---|
| VPC | `kops-vpc` |
| Subnet | `kops-subnet` |
| Auto-assign Public IP | Enable |
| Security Group | `kops-sg` |

7. Configure the required storage.
8. Launch the instance.

### Step-04.7: Connect to the EC2 Instance

Use SSH from your terminal or preferred SSH client:

```bash
ssh -i <key-file.pem> ubuntu@<EC2-PUBLIC-IP>
```

Update Ubuntu packages:

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

Verify the operating system:

```bash
lsb_release -a
```

---

## Step-05: IAM and S3 Configuration

### Step-05.1: Create an IAM Role for the EC2 Instance

KOPS needs AWS permissions to create and manage cluster resources.

In this lab, an IAM role is attached to the administration EC2 instance so that AWS CLI and KOPS can obtain temporary credentials from the instance role.

1. Open **IAM → Roles → Create role**.
2. Select **AWS service** as the trusted entity type.
3. Choose **EC2** as the use case.
4. Attach the permissions required for the KOPS lab.

The original lab setup uses administrator access for the practice environment.

For a production environment, use a least-privilege IAM policy containing only the permissions required by the KOPS version and enabled AWS resources.

5. Give the role a name:

   ```text
   kops-admin-role
   ```

6. Create the role.

### Step-05.2: Attach the IAM Role to EC2

1. Open **EC2 → Instances**.
2. Select the `kops-admin` instance.
3. Choose **Actions → Security → Modify IAM role**.
4. Select `kops-admin-role`.
5. Update or attach the role.

Verify the instance identity from the EC2 terminal:

```bash
aws sts get-caller-identity
```

The returned ARN should identify the attached IAM role.

### Step-05.3: Create an S3 Bucket for KOPS State

KOPS stores cluster configuration and state in an S3 bucket.

The lab uses the domain name as the bucket name:

```text
rushilabs.in
```

S3 bucket names must be globally unique. If this name is unavailable, choose another unique bucket name and use it consistently in all KOPS commands.

Create the bucket in `us-east-1`:

```bash
aws s3api create-bucket \
  --bucket rushilabs.in \
  --region us-east-1
```

Enable versioning:

```bash
aws s3api put-bucket-versioning \
  --bucket rushilabs.in \
  --versioning-configuration Status=Enabled
```

Verify:

```bash
aws s3api get-bucket-versioning \
  --bucket rushilabs.in

aws s3 ls s3://rushilabs.in
```

Set the KOPS state store:

```bash
export KOPS_STATE_STORE=s3://rushilabs.in
```

---

## Step-06: KOPS and kubectl Installation

### Step-06.1: Install KOPS

Connect to the Ubuntu administration EC2 instance.

Download KOPS:

```bash
curl -Lo kops https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
```

Make it executable:

```bash
chmod +x kops
```

Move the binary into the executable path:

```bash
sudo mv kops /usr/local/bin/kops
```

Verify:

```bash
kops version
```

### Step-06.2: Install kubectl

`kubectl` is the command-line tool used to communicate with the Kubernetes API server.

**Important:** Download the kubectl binary and its checksum file using the same Kubernetes release version.

Do not download one file using `stable.txt` and the other using a separately specified version, because the stable release can change between downloads.

#### Step 1: Set the kubectl Version

For this lab, use `v1.37.0`:

```bash
KUBECTL_VERSION=v1.37.0
```

#### Step 2: Download the kubectl Binary

```bash
curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
```

#### Step 3: Download the Matching Checksum File

```bash
curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
```

#### Step 4: Verify the Checksum

```bash
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
```

Expected output:

```text
kubectl: OK
```

If the output is `FAILED` or reports an invalid checksum format, do not install that downloaded binary.

Check that both download URLs use exactly the same `${KUBECTL_VERSION}`, then download both files again.

#### Step 5: Install kubectl

After checksum verification succeeds:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

#### Step 6: Verify the Installation

```bash
which kubectl
kubectl version --client
```

Expected output for this lab:

```text
/usr/local/bin/kubectl
Client Version: v1.37.0
Kustomize Version: v5.8.1
```

The exact Kustomize version may vary.

#### Step 7: Clean Up Downloaded Files

After successful installation and verification:

```bash
rm -f kubectl kubectl.sha256
```

### Step-06.3: Troubleshooting – Checksum Verification Failed

If you see:

```text
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

Possible causes include downloading the binary and checksum from different release versions or an incomplete/incorrect download.

Download both files again using the same version:

```bash
KUBECTL_VERSION=v1.37.0

curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"

echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
```

Proceed with installation only when the result is:

```text
kubectl: OK
```

> **Note:** If you run the commands as `root`, `~` refers to `/root`. Installing to `/usr/local/bin` makes the command available system-wide and avoids confusion between `/usr/local/bin/kubectl` and `~/.local/bin/kubectl`.

> **Version Compatibility:** For a repeatable or production deployment, pin KOPS, Kubernetes, and kubectl versions and verify their compatibility. Use the KOPS release documentation to select a supported Kubernetes version.

---

## Step-07: SSH Key and DNS Configuration

### Step-07.1: Generate an SSH Key

KOPS uses an SSH public key to configure access to cluster instances.

Check for an existing key:

```bash
ls -la ~/.ssh/
```

Generate an ED25519 key if required.

Do not overwrite an existing key that is already in use.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

Set permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

Verify the public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Use the public key path in the KOPS cluster creation command.

The path must match the Linux user running KOPS.

For example:

- When running as root, `~` refers to `/root`.
- When running as ubuntu, `~` refers to `/home/ubuntu`.

### Step-07.2: Configure KOPS Environment Variables

Create an environment file:

```bash
sudo vim /home/ubuntu/ClusterCreation.sh
```

Add:

```bash
export CLUSTER_NAME=rushilabs.in
export NAME=rushilabs.in
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
export KOPS_STATE_STORE=s3://rushilabs.in
export KUBE_EDITOR=vim
```

Load it into the current shell:

```bash
source /home/ubuntu/ClusterCreation.sh
```

Verify:

```bash
echo "$CLUSTER_NAME"
echo "$AWS_REGION"
echo "$KOPS_STATE_STORE"
```

If KOPS is run as a different Linux user, ensure the environment file and SSH public key path are accessible to that user.

### Step-07.3: Create a DNS Test Record

Before cluster creation, create a test DNS record to verify that GoDaddy-to-Route 53 delegation is working.

1. Open **Route 53 → Hosted zones → rushilabs.in**.
2. Choose **Create record**.
3. Create a record such as:

| Setting | Example |
|---|---|
| Record Name | `demo` |
| Record Type | `A` |
| Value | `10.20.30.40` |
| TTL | Default |

4. Save the record.

The IP `10.20.30.40` is an example private IP used only to test DNS resolution.

It is not a public endpoint and should not be used as a real internet-facing application address.

### Step-07.4: Test DNS Resolution from the EC2 Server

Install DNS utilities if required:

```bash
sudo apt-get install -y dnsutils
```

Run:

```bash
nslookup demo.rushilabs.in
```

Example output:

```text
Server:     127.0.0.53
Address:    127.0.0.53#53

Non-authoritative answer:
Name:       demo.rushilabs.in
Address:    10.20.30.40
```

You can also use:

```bash
dig demo.rushilabs.in
```

If the record does not resolve, verify:

- Route 53 record.
- Four nameservers configured in GoDaddy.
- DNS propagation.

---

## Step-08: Kubernetes Cluster Creation

### Step-08.1: Lab Cluster Configuration

| Parameter | Value |
|---|---|
| Cluster Name | `rushilabs.in` |
| AWS Region | `us-east-1` |
| Availability Zone | `us-east-1a` |
| KOPS State Store | `s3://rushilabs.in` |
| Control-Plane Count | `1` |
| Worker Node Count | `3` |
| Instance Type | `t3.medium` |
| Control-Plane Volume | `10 GB` |
| Worker Volume | `10 GB` |
| Networking | `Calico` |
| SSH Public Key | `/root/.ssh/id_ed25519.pub` |
| DNS Hosted Zone | `rushilabs.in` |

The SSH public key path above matches the root-user lab setup.

If you run KOPS as `ubuntu`, use the corresponding key under `/home/ubuntu/.ssh/`.

### Step-08.2: Create the Kubernetes Cluster

```bash
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

Review the cluster configuration and expected AWS resources before confirming creation in a production environment.

### Step-08.3: Inspect KOPS Configuration

List the cluster:

```bash
kops get cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

List instance groups:

```bash
kops get instancegroups \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

If you make configuration changes that have not yet been applied, review the update plan:

```bash
kops update cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

After reviewing the changes, apply them:

```bash
kops update cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --yes
```

### Step-08.4: Raft Consensus and Control-Plane Availability

Kubernetes uses etcd as its distributed key-value store.

etcd uses the Raft consensus algorithm to maintain consistency among its members.

For a three-member etcd control-plane quorum:

- A majority of members must be available to make progress.
- Three members can tolerate one member failure.
- If two of the three members are unavailable, quorum is lost.

The lab command above creates **one control-plane node** for a basic practice cluster.

A highly available control plane requires a separate multi-control-plane design, typically with an odd number of control-plane/etcd members such as three.

Do not interpret the one-control-plane lab as an HA deployment.

---

## Step-09: Cluster Validation and Troubleshooting

### Step-09.1: Validate the Cluster

```bash
kops validate cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

Allow time for EC2 instances, networking, and Kubernetes components to initialize.

### Step-09.2: Export kubeconfig

```bash
kops export kubecfg \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --admin
```

Protect the kubeconfig file because it contains privileged cluster credentials.

### Step-09.3: Verify Kubernetes Access

Check the cluster endpoint:

```bash
kubectl cluster-info
```

Check nodes:

```bash
kubectl get nodes -o wide
```

Check namespaces:

```bash
kubectl get namespaces
```

Check all pods:

```bash
kubectl get pods -A
```

The lab is configured for four nodes:

- One control-plane node.
- Three worker nodes.

All nodes should eventually report `Ready`.

### Step-09.4: Check System Pods

```bash
kubectl get pods -n kube-system
```

For a pod that is not healthy:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Check logs:

```bash
kubectl logs <pod-name> -n <namespace>
```

### Step-09.5: Common Troubleshooting Commands

**Check AWS Identity:**

```bash
aws sts get-caller-identity
```

**Check the KOPS State Store:**

```bash
echo "$KOPS_STATE_STORE"
aws s3 ls s3://rushilabs.in
```

**Check DNS:**

```bash
dig NS rushilabs.in
dig api.rushilabs.in
nslookup demo.rushilabs.in
```

**Check SSH Key:**

```bash
ls -l ~/.ssh/
```

**Check KOPS Cluster and Instance Groups:**

```bash
kops get clusters
```

```bash
kops get instancegroups --name="${CLUSTER_NAME}"
```

**Check kubeconfig Context:**

```bash
kubectl config current-context
kubectl config get-contexts
```

**Check Nodes and Pods:**

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Step-09.6: Common Issues and Solutions

| Issue | What to Verify |
|---|---|
| AWS `AccessDenied` | Active IAM role and required permissions |
| S3 bucket not found | Bucket name, region, and state-store value |
| SSH public key not found | Correct key path and Linux user |
| DNS does not resolve | Route 53 record, GoDaddy nameservers, propagation |
| Kubernetes API unreachable | API DNS record, kubeconfig, network path, security groups |
| Node is `NotReady` | EC2 instance state, node events, CNI/system pods |
| Cluster validation fails | KOPS validation output, instance groups, node and pod status |

---

## Step-10: Kubernetes Cluster Deletion

### Step-10.1: Important Before Deletion

Cluster deletion is destructive.

It can remove EC2 instances and other infrastructure managed by KOPS.

Before deleting:

- Back up required application data.
- Confirm the target cluster name.
- Verify the KOPS state store.
- Make sure you are deleting the correct cluster.

### Step-10.2: Review the Cluster

```bash
kops get cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

Review instance groups:

```bash
kops get instancegroups \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}"
```

### Step-10.3: Delete the KOPS Cluster

```bash
kops delete cluster \
  --name=rushilabs.in \
  --state=s3://rushilabs.in \
  --yes
```

### Step-10.4: Check for Remaining AWS Resources

After deletion, review the AWS Console for resources that may remain or incur charges, including:

- EC2 instances and EBS volumes.
- Load balancers.
- Elastic IP addresses.
- VPC, subnets, Internet Gateway, and route tables.
- Route 53 records.

Deleting the KOPS cluster does not automatically mean the following are deleted:

- S3 state bucket.
- Route 53 hosted zone.
- GoDaddy domain registration.

Review these separately and retain them if they are needed for future labs.

---

## Step-11: Lab Completion Checklist

- [ ] AWS account and region ready.
- [ ] Domain `rushilabs.in` purchased through GoDaddy.
- [ ] Route 53 public hosted zone created.
- [ ] Four Route 53 nameservers copied into GoDaddy.
- [ ] DNS delegation verified.
- [ ] VPC created.
- [ ] One subnet created.
- [ ] Internet Gateway and route table configured.
- [ ] `kops-sg` security group created.
- [ ] Ubuntu 24.04 `t3.medium` administration EC2 instance launched.
- [ ] IAM role created and attached to EC2.
- [ ] S3 state bucket created and versioning enabled.
- [ ] KOPS installed.
- [ ] kubectl installed and verified.
- [ ] SSH key generated or verified.
- [ ] KOPS environment variables configured.
- [ ] DNS test record created and resolved.
- [ ] Kubernetes cluster created.
- [ ] KOPS cluster validation completed.
- [ ] kubectl access verified.
- [ ] Nodes and system pods checked.

---

## Step-12: Quick Command Reference

**AWS Identity:**

```bash
aws sts get-caller-identity
```

**KOPS Version:**

```bash
kops version
```

**kubectl Version:**

```bash
kubectl version --client
```

**KOPS State Store:**

```bash
export KOPS_STATE_STORE=s3://rushilabs.in
```

**DNS Tests:**

```bash
dig NS rushilabs.in
nslookup demo.rushilabs.in
```

**List KOPS Clusters:**

```bash
kops get clusters
```

**Validate Cluster:**

```bash
kops validate cluster --name="${CLUSTER_NAME}"
```

**Export kubeconfig:**

```bash
kops export kubecfg --name="${CLUSTER_NAME}" --admin
```

**Kubernetes Nodes:**

```bash
kubectl get nodes -o wide
```

**All Pods:**

```bash
kubectl get pods -A
```

**Delete Cluster – Destructive:**

```bash
kops delete cluster --name="${CLUSTER_NAME}" --yes
```

---

**End of Module: KOPS on AWS**
