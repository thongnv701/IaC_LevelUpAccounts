module "network" {
  source            = "./modules/network"
  vpc_cidr          = "10.0.0.0/16"
  subnet_cidr       = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"
  allowed_cidr      = var.allowed_cidr
}

module "compute" {
  source             = "./modules/compute"
  ami                = "ami-05ab12222a9f39021"
  instance_type      = "t3.small"
  key_name           = "aws-keypair-2"
  subnet_id          = module.network.subnet_id
  security_group_id  = module.network.security_group_id
  private_key_content = var.private_key_content
  master_user_data   = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1
    sudo yum update -y
    sudo yum install -y iptables
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    echo "Public IP: $PUBLIC_IP"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --tls-san $PUBLIC_IP --disable traefik" sh -s - --debug
    sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s-node-token
    sudo /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/master=:NoSchedule || true
    echo "K3s master setup complete."
    EOF
  worker_user_data    = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1

    # Create .ssh directory and set up private key for SSH access
    mkdir -p /home/ec2-user/.ssh
    cat <<'KEY' > /home/ec2-user/.ssh/id_rsa
    ${var.private_key_content}
    KEY
    chmod 600 /home/ec2-user/.ssh/id_rsa
    chown ec2-user:ec2-user /home/ec2-user/.ssh/id_rsa

    # Update system and install required packages
    yum update -y
    yum install -y nmap-ncat

    # Set the master node's private IP
    MASTER_IP="${module.compute.master_private_ip}"

    # Wait for master API server to be ready
    while ! nc -z $MASTER_IP 6443; do
      echo "Waiting for k3s master at $MASTER_IP:6443..."
      sleep 5
    done

    # Wait for /tmp/k3s-node-token to exist on master
    for i in {1..30}; do
      if ssh -o StrictHostKeyChecking=no -i /home/ec2-user/.ssh/id_rsa ec2-user@$MASTER_IP "test -f /tmp/k3s-node-token"; then
        break
      fi
      echo "Waiting for /tmp/k3s-node-token to be available on master..."
      sleep 5
    done

    # Fetch the node token
    if ! scp -o StrictHostKeyChecking=no -i /home/ec2-user/.ssh/id_rsa ec2-user@$MASTER_IP:/tmp/k3s-node-token /tmp/k3s-node-token; then
      echo "Failed to fetch k3s node token from master"
      exit 1
    fi
    TOKEN=$(cat /tmp/k3s-node-token)

    # Install and join the worker node to the cluster
    curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN="$TOKEN" sh -

    # Set up kubeconfig for the worker
    mkdir -p /home/ec2-user/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
    sed -i "s/127.0.0.1/$MASTER_IP/g" /home/ec2-user/.kube/config
    chown -R ec2-user:ec2-user /home/ec2-user/.kube

    echo "K3s worker setup complete."
  EOF

  kubeconfig_fetch_script = file("${path.module}/kubeconfig_fetch.sh")
}

provider "kubernetes" {
  alias       = "with_config"
  config_path = "${abspath(path.root)}/modules/compute/kubeconfig"
}

provider "helm" {
  alias = "with_config"
  kubernetes {
    config_path = "${abspath(path.root)}/modules/compute/kubeconfig"
  }
}

module "kubernetes" {
  source      = "./modules/kubernetes"
  rds_password = var.rds_password
  rds_username = var.rds_username
  rds_endpoint = var.rds_endpoint
  # depends_on = [
  #   null_resource.wait_for_cluster
  # ]
  providers = {
    kubernetes.with_config = kubernetes.with_config
  }
}

// Add this temporarily to main.tf to test the Helm provider
# modules/kubernetes/main.tf
# ArgoCD Helm Chart
resource "null_resource" "wait_for_coredns" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n kube-system wait --for=condition=Ready --timeout=300s pod -l k8s-app=kube-dns"
  }
}

module "monitoring" {
  source = "./modules/monitoring"
  rds_endpoint = var.rds_endpoint
  rds_username = var.rds_username
  depends_on = [
    module.kubernetes,
    null_resource.wait_for_coredns
  ]
  providers = {
    helm.with_config = helm.with_config
  }
}