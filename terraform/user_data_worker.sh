#!/bin/bash
set -e

# Update and install dependencies
sudo yum update -y
sudo yum install -y nmap-ncat

# Set the master node's private IP (replace this with actual value via Terraform template if needed)
MASTER_IP="${master_private_ip}"   # Replace with actual master private IP

# Wait for the master node to be ready
while ! nc -z $MASTER_IP 6443; do
  echo "Waiting for k3s master at $MASTER_IP:6443..."
  sleep 5
done

# Fetch the node token from the master (requires SSH key and access)
TOKEN=$(ssh -o StrictHostKeyChecking=no -i /home/ec2-user/.ssh/id_rsa ec2-user@$MASTER_IP "sudo cat /tmp/k3s-node-token")

# Join the cluster
curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN="$TOKEN" sh -

echo "K3s worker setup complete."