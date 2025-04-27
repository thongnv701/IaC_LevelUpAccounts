kubeconfig_fetch_script = [
  "set -e",
  "for i in {1..60}; do if [ -f /etc/rancher/k3s/k3s.yaml ]; then break; fi; echo 'Waiting for kubeconfig...'; sleep 5; done",
  "sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/kubeconfig",
  "sudo chown ubuntu:ubuntu /home/ubuntu/kubeconfig",
  "PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)",
  "sed -i \"s/127.0.0.1/$PUBLIC_IP/\" /home/ubuntu/kubeconfig",
  "echo 'Kubeconfig fetched and updated.'"
]