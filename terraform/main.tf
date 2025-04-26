# Configure remote state backend (uncomment and configure for production)
# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state"
#     key            = "k3s-cluster/terraform.tfstate"
#     region         = "ap-southeast-1"
#   }
# }

# Providers
provider "aws" {
  region = "ap-southeast-1"
}

provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig"
  }
}

# Retrieve RDS password from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = "my-rds-password-secret"  # Replace with your secret ID
}

# VPC and Subnet
resource "aws_vpc" "k3s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k3s-vpc"
  }
}

resource "aws_subnet" "k3s_subnet" {
  vpc_id            = aws_vpc.k3s_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "k3s-subnet"
  }
}

# Security Group
resource "aws_security_group" "k3s_security_group" {
  name        = "k3s-security-group"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.k3s_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k3s-security-group"
  }
}

# Master Node
resource "aws_instance" "k3s_master" {
  ami                         = "ami-05ab12222a9f39021"  # Ubuntu 22.04 LTS
  instance_type               = "t2.micro"
  key_name                    = "aws-keypair-2"
  subnet_id                   = aws_subnet.k3s_subnet.id
  vpc_security_group_ids      = [aws_security_group.k3s_security_group.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    echo "Starting K3s installation..." >> /var/log/user-data.log
    sudo apt update >> /var/log/user-data.log 2>&1
    sudo apt install -y curl iptables >> /var/log/user-data.log 2>&1
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --tls-san ${aws_instance.k3s_master.public_ip} --disable traefik" sh -s - --debug >> /var/log/user-data.log 2>&1
    if [ $? -ne 0 ]; then
      echo "K3s installation failed." >> /var/log/user-data.log
      exit 1
    fi
    sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s-node-token
    if [ $? -ne 0 ]; then
      echo "Failed to save K3s token." >> /var/log/user-data.log
      exit 1
    fi
    kubectl taint node $(hostname) node-role.kubernetes.io/master:NoSchedule >> /var/log/user-data.log 2>&1
    echo "K3s installation completed successfully." >> /var/log/user-data.log
  EOF

  tags = {
    Name = "k3s-master"
  }
}

# Fetch Kubeconfig
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [aws_instance.k3s_master]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = aws_instance.k3s_master.public_ip
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
    inline = [
      "for i in {1..60}; do if [ -f /etc/rancher/k3s/k3s.yaml ]; then break; fi; echo 'Waiting for kubeconfig...'; sleep 5; done",
      "sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/kubeconfig",
      "sudo chown ubuntu:ubuntu /home/ubuntu/kubeconfig",
      "sed -i 's/127.0.0.1/${aws_instance.k3s_master.public_ip}/' /home/ubuntu/kubeconfig"
    ]
  }

  provisioner "local-exec" {
    command = "scp -i ${var.private_key_path} ubuntu@${aws_instance.k3s_master.public_ip}:/home/ubuntu/kubeconfig ${path.module}/kubeconfig"
  }
}

# Worker Nodes
resource "aws_instance" "k3s_worker" {
  count                       = 2
  ami                         = "ami-05ab12222a9f39021"
  instance_type               = "t2.micro"
  key_name                    = "aws-keypair-2"
  subnet_id                   = aws_subnet.k3s_subnet.id
  vpc_security_group_ids      = [aws_security_group.k3s_security_group.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    for i in {1..60}; do
      if curl --output /dev/null --silent --head --fail http://${aws_instance.k3s_master.private_ip}:6443; then
        break
      fi
      echo "Waiting for master node..." >> /var/log/user-data.log
      sleep 5
    done
    TOKEN=$(ssh -i /home/ubuntu/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@${aws_instance.k3s_master.private_ip} "sudo cat /tmp/k3s-node-token")
    if [ -z "$TOKEN" ]; then
      echo "Failed to retrieve K3s token" >> /var/log/user-data.log
      exit 1
    fi
    curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.k3s_master.private_ip}:6443 K3S_TOKEN="$TOKEN" sh - >> /var/log/user-data.log 2>&1
    if [ $? -ne 0 ]; then
      echo "K3s worker installation failed." >> /var/log/user-data.log
      exit 1
    fi
    NODE_ROLE="worker-${count.index}"
    if [ "$NODE_ROLE" == "worker-0" ]; then
      kubectl label node $(hostname) workload=prometheus-postgres
    elif [ "$NODE_ROLE" == "worker-1" ]; then
      kubectl label node $(hostname) workload=loki
    fi
    echo "K3s worker installation completed." >> /var/log/user-data.log
  EOF

  tags = {
    Name = "k3s-worker-${count.index}"
  }
}

# Kubernetes Namespaces
resource "kubernetes_namespace" "monitoring" {
  depends_on = [null_resource.fetch_kubeconfig]

  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "argocd" {
  depends_on = [null_resource.fetch_kubeconfig]

  metadata {
    name = "argocd"
  }
}

# Kubernetes Secret for Postgres Exporter
resource "kubernetes_secret" "postgres_exporter_credentials" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "postgres-exporter-credentials"
    namespace = "monitoring"
  }

  data = {
    password = data.aws_secretsmanager_secret_version.rds_password.secret_string
  }
}

# Helm Releases
resource "helm_release" "prometheus" {
  depends_on = [kubernetes_namespace.monitoring]
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "15.0.0"
  namespace  = "monitoring"

  set {
    name  = "server.nodeSelector.workload"
    value = "prometheus-postgres"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }
}

resource "helm_release" "loki" {
  depends_on = [kubernetes_namespace.monitoring]
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.8.0"
  namespace  = "monitoring"

  set {
    name  = "loki.nodeSelector.workload"
    value = "loki"
  }

  set {
    name  = "loki.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "loki.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "loki.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "loki.resources.limits.memory"
    value = "512Mi"
  }
}

resource "helm_release" "grafana" {
  depends_on = [kubernetes_namespace.monitoring]
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "6.50.0"
  namespace  = "monitoring"

  set {
    name  = "tolerations[0].key"
    value = "node-role.kubernetes.io/master"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "datasources.\"datasources.yaml\".apiVersion"
    value = "1"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[0].name"
    value = "Prometheus"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[0].type"
    value = "prometheus"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[0].url"
    value = "http://prometheus-server.monitoring.svc.cluster.local"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[0].access"
    value = "proxy"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[1].name"
    value = "Loki"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[1].type"
    value = "loki"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[1].url"
    value = "http://loki.monitoring.svc.cluster.local"
  }

  set {
    name  = "datasources.\"datasources.yaml\".datasources[1].access"
    value = "proxy"
  }
}

resource "helm_release" "argocd" {
  depends_on = [kubernetes_namespace.argocd]
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.0.0"
  namespace  = "argocd"

  set {
    name  = "server.tolerations[0].key"
    value = "node-role.kubernetes.io/master"
  }

  set {
    name  = "server.tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "server.tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/master"
  }

  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "256Mi"
  }
}

resource "helm_release" "postgres_exporter" {
  depends_on = [kubernetes_namespace.monitoring, kubernetes_secret.postgres_exporter_credentials]
  name       = "postgres-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-postgres-exporter"
  version    = "2.0.0"
  namespace  = "monitoring"
  values     = [file("${path.module}/../helm/postgres-exporter/values.yaml")]

  set {
    name  = "config.datasource.host"
    value = var.rds_endpoint
  }

  set {
    name  = "config.datasource.user"
    value = var.rds_username
  }
}

# ArgoCD Application
resource "kubernetes_manifest" "argocd_app" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "my-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/your-org/your-app-config.git"
        targetRevision = "HEAD"
        path           = "manifests"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

# Outputs
output "master_public_ip" {
  value = aws_instance.k3s_master.public_ip
}

output "worker_public_ips" {
  value = aws_instance.k3s_worker[*].public_ip
}