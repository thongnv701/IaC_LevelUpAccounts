provider "aws" {
  region = "ap-southeast-1"
}

module "network" {
  source             = "./modules/network"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["ap-southeast-1a", "ap-southeast-1b"]
  allowed_cidr      = var.allowed_cidr
}

module "compute" {
  source             = "./modules/compute"
  ami                = "ami-05ab12222a9f39021"
  master_instance_type      = "t3.small"
  worker_instance_type      = "t2.small"
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

# module "kubernetes" {
#   source      = "./modules/kubernetes"
#   rds_password = var.rds_password
#   rds_username = var.rds_username
#   rds_endpoint = var.rds_endpoint
#   # depends_on = [
#   #   null_resource.wait_for_cluster
#   # ]
#   providers = {
#     kubernetes.with_config = kubernetes.with_config
#   }
# }

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
    null_resource.wait_for_coredns,
    null_resource.wait_for_prometheus_operator
  ]
  providers = {
    helm = helm.with_config
  }
}

provider "helm" {
  alias = "with_config"
  kubernetes {
    config_path = "${abspath(path.root)}/modules/compute/kubeconfig"
  }
}

resource "helm_release" "prometheus_operator" {
  provider   = helm.with_config
  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = "monitoring"
  create_namespace = true

  set {
    name  = "grafana.enabled"
    value = "false"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }

  set {
    name  = "prometheus.serviceMonitor.selfMonitor"
    value = "true"
  }

  # Add timeout to prevent long waits
  timeout = 600
}

resource "null_resource" "wait_for_prometheus_operator" {
  depends_on = [helm_release.prometheus_operator]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n monitoring wait --for=condition=ready pod -l app=kube-prometheus-stack-operator --timeout=300s"
  }
}

resource "helm_release" "nginx_ingress" {
  provider   = helm.with_config
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.1"
  namespace  = "ingress-nginx"
  create_namespace = true
  timeout    = 600

  values = [
    file("${abspath(path.root)}/../helm/ngix-ingress/values.yaml")
  ]

  depends_on = [
    null_resource.wait_for_prometheus_operator
  ]

  # Add retry logic
  wait = true
  wait_for_jobs = true
  atomic = true
}

# Add a wait for the NGINX Ingress Controller to be ready
resource "null_resource" "wait_for_nginx_ingress" {
  depends_on = [helm_release.nginx_ingress]
  provisioner "local-exec" {
    command = <<-EOC
      kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s
    EOC
  }
}

data "kubernetes_service" "nginx_ingress" {
  provider = kubernetes.with_config
  depends_on = [null_resource.wait_for_nginx_ingress]
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# Get the Load Balancer hostname from the Nginx Ingress Controller service
# locals {
#   load_balancer_hostname = data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.hostname
#   # If hostname is empty, use IP address
#   load_balancer_ip = try(data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip, "")
#   load_balancer_endpoint = coalesce(local.load_balancer_hostname, local.load_balancer_ip)
# }

resource "helm_release" "argocd" {
  provider         = helm.with_config
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.0"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600
  wait             = true

  values = [
    file("${abspath(path.root)}/../helm/argocd/values.yaml")
  ]

  depends_on = [
    null_resource.wait_for_nginx_ingress
  ]
}

# wait for argocd server and redis to be ready
resource "null_resource" "wait_for_argocd" {
  depends_on = [
    helm_release.argocd
  ]
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<-EOC
      kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n argocd wait --for=condition=Available --timeout=300s deployment/argocd-server && \
      kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n argocd wait --for=condition=Ready --timeout=300s pod -l app.kubernetes.io/name=argocd-redis
    EOC
  }
}

# Add Route 53 configuration
# resource "aws_route53_record" "argocd" {
#   zone_id = var.route53_zone_id # You'll need to add this variable
#   name    = "argocd.thongit.space"
#   type    = "A"
  
#   alias {
#     name                   = local.load_balancer_hostname
#     zone_id                = var.route53_elb_zone_id # You'll need to add this variable
#     evaluate_target_health = true
#   }
  
#   depends_on = [data.kubernetes_service.nginx_ingress, null_resource.wait_for_argocd]
# }
