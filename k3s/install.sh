#!/bin/bash

# Install k3s on master node
curl -sfL https://get.k3s.io | sh -

# Retrieve the k3s token for worker nodes
sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s-node-token

echo "k3s installed successfully. Node token saved to /tmp/k3s-node-token."