#!/bin/bash
set -e

# Update and install dependencies
sudo yum update -y
sudo yum install -y iptables

# Get the public IP from EC2 metadata
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Install k3s with public IP as TLS SAN and disable traefik
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --tls-san $PUBLIC_IP --disable traefik" sh -s - --debug

# Save the k3s token for worker nodes to join
sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s-node-token

# Optional: Taint master node to prevent workloads (remove if you want to schedule pods on master)
sudo /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/master=:NoSchedule || true

echo "K3s master setup complete."