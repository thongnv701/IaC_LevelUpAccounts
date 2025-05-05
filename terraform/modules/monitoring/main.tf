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