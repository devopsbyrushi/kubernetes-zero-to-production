
# KOPS on AWS – Kubernetes Cluster Automation Using Bash

## Overview

In this module, we will automate AWS infrastructure provisioning and Kubernetes cluster deployment using Bash scripting and AWS CLI.

We will first complete the required AWS and domain configurations manually. After completing these prerequisites, we will use a single Bash script to provision the AWS infrastructure, install KOPS and kubectl, and create a Kubernetes cluster.

We will also maintain a separate Bash script for deleting the Kubernetes cluster and its AWS infrastructure.

## Architecture and Workflow

The complete implementation is divided into two phases:

### Phase-01: Manual Prerequisites

1. AWS account and required permissions.
2. Domain purchase from GoDaddy.
3. Route 53 public hosted zone creation.
4. GoDaddy nameserver configuration.
5. DNS propagation verification.

### Phase-02: Bash Automation

We will automate the following activities using a single Bash script:

1. Configure AWS CLI.
2. Create VPC.
3. Create public subnet.
4. Create Internet Gateway.
5. Configure route table.
6. Create security group.
7. Create IAM role and attach required permissions.
8. Create S3 bucket and enable versioning.
9. Launch a new EC2 instance.
10. Install KOPS.
11. Install kubectl.
12. Generate SSH key.
13. Configure KOPS environment variables.
14. Create Kubernetes cluster.
15. Export kubeconfig.
16. Validate Kubernetes cluster.
17. Verify control-plane and worker nodes.

## Step-01: AWS Prerequisites

Before starting the automation, make sure you have:

- AWS account with billing enabled.
- AWS console access.
- Required IAM permissions.
- GoDaddy account.
- Domain name.
- AWS region: `us-east-1`.

## Step-02: Domain Purchase and Route 53 Configuration

Complete the following activities manually:

### Step-02.1: Purchase Domain

Purchase a domain from GoDaddy.

Example:

```text
Domain Name: rushilabs.in
Domain Provider: GoDaddy
```

### Step-02.2: Create Route 53 Hosted Zone

1. Log in to AWS Management Console.
2. Open Route 53.
3. Navigate to Hosted Zones.
4. Create a public hosted zone.
5. Enter your domain name.
6. Copy the four AWS nameservers.

### Step-02.3: Update GoDaddy Nameservers

1. Log in to GoDaddy.
2. Open your domain DNS settings.
3. Select custom nameservers.
4. Enter all four Route 53 nameservers.
5. Save the configuration.

### Step-02.4: Verify DNS Configuration

Verify that the domain is delegated to AWS Route 53 and that DNS records can be resolved.

## Step-03: Bash Automation – AWS Infrastructure and KOPS Cluster

After completing the manual prerequisites, we will execute one Bash script.

### Script Name

`create-kops-cluster.sh`

This script automates AWS infrastructure creation, KOPS installation and Kubernetes cluster deployment.

### AWS Infrastructure Configuration

| Resource | Configuration |
|---|---|
| AWS Region | us-east-1 |
| Availability Zone | us-east-1a |
| VPC CIDR | 10.0.0.0/16 |
| Public Subnet CIDR | 10.0.1.0/24 |
| EC2 Instance | t3.medium |
| Operating System | Ubuntu 24.04 LTS |
| S3 State Bucket | rushilabs.in |
| Cluster Name | rushilabs.in |

### Kubernetes Cluster Configuration

| Component | Configuration |
|---|---|
| Control Plane | 1 |
| Worker Nodes | 3 |
| Instance Type | t3.medium |
| Networking | Calico |
| Kubernetes Management | KOPS |
| Command-Line Tool | kubectl |

### Step-03.1: Execute Automation Script

Connect to your AWS administration environment and execute:

```bash
chmod +x create-kops-cluster.sh
./create-kops-cluster.sh
```

The script will provision the required AWS resources, install the necessary tools and create the Kubernetes cluster.

### Step-03.2: Validate Kubernetes Cluster

After cluster creation, verify the cluster status.

```bash
kops validate cluster --wait=20m
```

Check cluster information:

```bash
kubectl cluster-info
```

Check Kubernetes nodes:

```bash
kubectl get nodes -o wide
```

Check all namespaces:

```bash
kubectl get pods -A
```

Expected result:

- One control-plane node.
- Three worker nodes.
- All four nodes in Ready status.

## Step-04: Kubernetes Cluster Deletion

We will use a separate Bash script to delete the Kubernetes cluster.

### Script Name

`delete-kops-cluster.sh`

Execute the script:

```bash
chmod +x delete-kops-cluster.sh
./delete-kops-cluster.sh
```

The script will:

1. Verify AWS credentials.
2. Identify the KOPS cluster.
3. Ask for deletion confirmation.
4. Delete the Kubernetes cluster.
5. Verify the deletion result.

## Step-05: AWS Infrastructure Cleanup

After successful Kubernetes cluster deletion, the automation can clean up the AWS resources created for this lab.

The cleanup process should:

1. Terminate the administration EC2 instance.
2. Delete the security group.
3. Delete the public subnet.
4. Delete the route table associations and custom route table.
5. Detach and delete the Internet Gateway.
6. Delete the VPC.
7. Remove the IAM role and associated policies created for this lab.
8. Delete the S3 state bucket only after confirming that it is no longer required.

**Important:** Do not delete the Route 53 hosted zone or GoDaddy domain as part of ordinary cluster cleanup. These are manual prerequisites and may be reused for future clusters.

## Final Project Structure

```text
KOPS-on-AWS/
│
├── 01-Manual-Prerequisites/
│   ├── 01-AWS-Prerequisites.md
│   └── 02-Domain-Purchase-and-Route53.md
│
├── 02-Bash-Automation/
│   ├── create-kops-cluster.sh
│   ├── delete-kops-cluster.sh
│   └── README.md
│
└── README.md
```

## Important Notes

- Complete AWS and domain prerequisites before executing the automation.
- Use the same AWS region throughout the deployment.
- Ensure the EC2 instance has the required IAM permissions.
- Keep the S3 KOPS state bucket private and enable versioning.
- Use SSH keys securely.
- Avoid opening SSH access to the entire internet.
- The cluster creation process takes time because AWS resources are provisioned asynchronously.
- Review the resources before running deletion scripts.
- The example configuration is intended for a training lab, not a production HA deployment.

## Author

**Rushi – Lead DevOps Engineer and Cloud**

RushiInfotech – DevOps and Cloud Technologies
