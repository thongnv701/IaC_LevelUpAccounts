
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