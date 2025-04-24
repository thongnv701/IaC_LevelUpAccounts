# Project: Backup and Manage ArgoCD Configurations

This project provides a step-by-step guide to set up a Kubernetes environment with K3s, Nginx Ingress, and ArgoCD. It is designed to help you manage and back up ArgoCD configurations effectively.

## Installations

### Install K3s without Traefik Ingress

K3s is a lightweight Kubernetes distribution. By default, it includes Traefik as the ingress controller. In this setup, we disable Traefik to use Nginx Ingress instead.

Run the following command to install K3s without Traefik:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --write-kubeconfig-mode 644 --disable traefik
```

### Install Nginx Ingress

Nginx Ingress will act as the ingress controller for your Kubernetes cluster. Use Helm to install it in the `ingress-nginx` namespace.

Run the following command:
```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

Verify the installation:
```bash
kubectl get pods -n ingress-nginx
```

### Install ArgoCD

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. Use Helm to install it in the `argocd` namespace.

Run the following command:
```bash
helm upgrade argocd argo-cd \
  --namespace argocd \
  --repo https://argoproj.github.io/argo-helm \
  --install \
  --create-namespace \
  --values ./helm-values/argocd.yaml
```

Verify the installation:
```bash
kubectl get pods -n argocd
```

Additional Notes:
- Ensure that the ./helm-values/argocd.yaml file contains the desired configuration for ArgoCD. You can customize this file based on your requirements.
- After installation, access the ArgoCD dashboard using the ingress or port-forwarding method.
- For more details about ArgoCD, refer to the [official documentation](https://argo-cd.readthedocs.io/en/stable/).