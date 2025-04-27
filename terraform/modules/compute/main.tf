resource "aws_instance" "k3s_master" {
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  user_data = var.master_user_data

  metadata_options {
    http_tokens   = "optional"   # Allow both IMDSv1 and IMDSv2
    http_endpoint = "enabled"    # Enable the metadata endpoint
  }

  tags = {
    Name = "k3s-master"
  }
}

resource "null_resource" "fetch_kubeconfig" {
  depends_on = [aws_instance.k3s_master]
  provisioner "remote-exec" {
  connection {
    type        = "ssh"
    host        = aws_instance.k3s_master.public_ip
    user        = "ec2-user" # <-- use ec2-user for Amazon Linux
    private_key = file(var.private_key_path)
  }
  inline = [
    "set -e",
    "for i in {1..60}; do if [ -f /etc/rancher/k3s/k3s.yaml ]; then break; fi; echo 'Waiting for kubeconfig...'; sleep 5; done",
    "sudo cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig",
    "sudo chown ec2-user:ec2-user /home/ec2-user/kubeconfig",
    "PUBLIC_IP=$(curl -s --connect-timeout 10 http://169.254.169.254/latest/meta-data/public-ipv4) || { echo 'Failed to fetch public IP' >> /tmp/fetch_kubeconfig.log; exit 1; }",
    "sed -i \"s/127.0.0.1/$PUBLIC_IP/g\" /home/ec2-user/kubeconfig 2>> /tmp/fetch_kubeconfig.log || { echo 'sed failed' >> /tmp/fetch_kubeconfig.log; exit 1; }",
    "echo 'Kubeconfig fetched and updated.' >> /tmp/fetch_kubeconfig.log",
    "exit 0"
  ]
  }
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${var.private_key_path} ec2-user@${aws_instance.k3s_master.public_ip}:/home/ec2-user/kubeconfig ${path.module}/kubeconfig"
  }
}

resource "aws_instance" "k3s_worker" {
  count                       = var.worker_count
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true
  user_data                   = var.worker_user_data
    metadata_options {
    http_tokens   = "optional"   # Allow both IMDSv1 and IMDSv2
    http_endpoint = "enabled"    # Enable the metadata endpoint
  }
  tags = {
    Name = "k3s-worker-${count.index}"
  }
}