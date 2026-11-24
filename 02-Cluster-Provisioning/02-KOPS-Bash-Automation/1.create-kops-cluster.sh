# Create an isolated network for the admin server and Kubernetes cluster.
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=kops-vpc}]" --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --vpc-ids "$VPC"
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames '{"Value":true}'

# Step-05: Create a public subnet
# Place resources in the selected availability zone and enable public IP assignment.
SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC" --availability-zone "$AZ" --cidr-block 10.0.1.0/24 --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET" --map-public-ip-on-launch

# Step-06: Create and attach the Internet Gateway
# Provide a path from the VPC to the internet.
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"

# Step-07: Configure the public route table
# Route internet-bound traffic through the gateway and associate the subnet.
RT=$(aws ec2 create-route-table --vpc-id "$VPC" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW"
ASSOC=$(aws ec2 associate-route-table --route-table-id "$RT" --subnet-id "$SUBNET" --query AssociationId --output text)

# Step-08: Create the admin security group
# Allow SSH on port 22 only from the supplied source CIDR.
SG=$(aws ec2 create-security-group --group-name kops-sg --description 'KOPS admin SSH' --vpc-id "$VPC" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$SSH_CIDR"

# Step-09: Create the IAM role and instance profile
# Allow EC2 to assume the role. AdministratorAccess is for this lab only.
aws iam create-role --role-name "$ROLE" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-instance-profile --instance-profile-name "$PROFILE"
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"

# Step-10: Generate and import the admin EC2 SSH key
# The private key remains on the machine running this script.
mkdir -p "$HOME/.ssh"
[[ -f $KEY ]] || ssh-keygen -q -t ed25519 -N '' -f "$KEY"
aws ec2 import-key-pair --key-name "$LAB" --public-key-material "fileb://${KEY}.pub"

# Step-11: Find the Ubuntu 24.04 AMI
# Resolve the regional image ID through the public SSM parameter.
AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)

# Step-12: Launch the admin EC2 instance
# Wait briefly for IAM permissions to propagate.
sleep 30
INSTANCE=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.medium --count 1 --client-token "${VPC}-admin" --subnet-id "$SUBNET" --security-group-ids "$SG" --associate-public-ip-address --key-name "$LAB" --iam-instance-profile "Name=$PROFILE" --metadata-options HttpTokens=required --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kops-admin-server}]' --query 'Instances[0].InstanceId' --output text)

# Step-13: Wait for EC2 readiness and establish SSH access
# Wait for EC2 and retrieve its public IP.
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE"
IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Step-14: Execute the remaining automation on the new EC2 instance
# Pass lab configuration to a remote Bash session over SSH.
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$IP" bash -s -- "$DOMAIN" "$BUCKET" "$REGION" "$AZ" "$VPC" "$SUBNET" "$SSH_CIDR" "$IP" <<'REMOTE'
set -e
DOMAIN=$1 BUCKET=$2 REGION=$3 AZ=$4 VPC=$5 SUBNET=$6 SSH_CIDR=$7 ADMIN_IP=$8
export AWS_DEFAULT_REGION="$REGION" KOPS_STATE_STORE="s3://$BUCKET" NAME="$DOMAIN"

# Step-15: Prepare Ubuntu and install required packages
# Wait for cloud-init before using the package manager.
sudo cloud-init status --wait
sudo apt-get update
sudo apt-get install -y curl unzip ca-certificates dnsutils
mkdir -p ~/kops-tools
cd ~/kops-tools

# Step-16: Install AWS CLI on the admin EC2
# Verify credentials supplied by the attached IAM role.
curl -fsSLo aws.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
unzip -q aws.zip
sudo ./aws/install
aws sts get-caller-identity

# Step-17: Install KOPS
# Download the latest release and verify that the executable runs.
curl -fsSLo kops https://github.com/kubernetes/kops/releases/latest/download/kops-linux-amd64
sudo install -m 0755 kops /usr/local/bin/kops
kops version

# Step-18: Generate the Kubernetes node SSH key
# Keep this key on the admin EC2 and check for an existing cluster.
mkdir -p "$HOME/.ssh"
[[ -f $HOME/.ssh/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
if kops get cluster "$NAME" >/dev/null 2>&1; then echo 'Cluster already exists; stopping.'; exit 1; fi

# Step-19: Generate the Kubernetes cluster configuration
# Use the existing VPC, subnet and hosted zone with one control plane and three workers.
# This command records the desired configuration; update cluster provisions it.
kops create cluster --name "$NAME" --cloud aws --zones "$AZ" --control-plane-zones "$AZ" --vpc "$VPC" --subnets "$SUBNET" --dns-zone "$DOMAIN" --node-count 3 --control-plane-count 1 --node-size t3.medium --control-plane-size t3.medium --networking calico --ssh-public-key "$HOME/.ssh/id_ed25519.pub" --admin-access "$SSH_CIDR,$ADMIN_IP/32" --ssh-access "$SSH_CIDR"

# Step-20: Install matching kubectl and verify its checksum
# Read the Kubernetes version from the KOPS cluster specification.
VERSION=$(kops get cluster "$NAME" -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["spec"]["kubernetesVersion"])')
VERSION=v${VERSION#v}
curl -fsSLO "https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl"
curl -fsSLO "https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -m 0755 kubectl /usr/local/bin/kubectl

# Step-21: Save KOPS environment variables for future sessions
# Source ~/ClusterCreation.sh when reconnecting to the admin server.
printf 'export AWS_DEFAULT_REGION=%q\nexport KOPS_STATE_STORE=%q\nexport NAME=%q\n' "$REGION" "$KOPS_STATE_STORE" "$NAME" > "$HOME/ClusterCreation.sh"

# Step-22: Provision Kubernetes cluster resources
# Apply the desired cluster configuration to AWS.
kops update cluster "$NAME" --yes

# Step-23: Export the administrator kubeconfig
# Configure kubectl to communicate with the Kubernetes API.
kops export kubecfg "$NAME" --admin

# Step-24: Validate the cluster and display nodes and pods
# Wait for cluster readiness and show the resulting Kubernetes resources.
kops validate cluster --wait=20m
kubectl get nodes -o wide
kubectl get pods -A
REMOTE

# Step-25: Display the admin server connection details
# Print the SSH command for subsequent administration.
printf 'Admin server: %s\nConnect: ssh -i %q ubuntu@%s\n' "$IP" "$KEY" "$IP"
