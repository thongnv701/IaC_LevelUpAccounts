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


resource "helm_release" "nginx_ingress" {
  provider   = helm.with_config
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.1" # Use latest stable

  namespace  = "ingress-nginx"
  create_namespace = true

  values = [
    file("${abspath(path.root)}/../helm/ngix-ingress/values.yaml")
  ]
}


resource "null_resource" "wait_for_nginx_ingress" {
  depends_on = [helm_release.nginx_ingress]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${abspath(path.root)}/modules/compute/kubeconfig -n ingress-nginx wait --for=condition=available --timeout=300s deployment/nginx-ingress-ingress-nginx-controller"
  }
}


data "kubernetes_service" "nginx_ingress" {
  provider = helm.with_config
  depends_on = [null_resource.wait_for_nginx_ingress]
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# data "aws_route53_zone" "main" {
#   name = "thongit.space."
# }

# resource "aws_route53_record" "argocd" {
#   depends_on = [data.kubernetes_service.nginx_ingress]
#   count   = can(data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].hostname) && data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].hostname != "" ? 1 : 0
#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = "argocd.thongit.space"
#   type    = "CNAME"
#   ttl     = 300
#   records = [data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].hostname]
# }