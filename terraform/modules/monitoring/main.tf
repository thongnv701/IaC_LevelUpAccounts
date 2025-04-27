resource "helm_release" "argocd" {
  provider   = helm.with_config
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.16" # You can update to the latest stable version if needed
  namespace  = "argocd"

  create_namespace = true

  # Optional: set values for custom configuration
  # values = [
  #   file("${path.module}/argocd-values.yaml")
  # ]

  
}