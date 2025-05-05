terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      configuration_aliases = [kubernetes.with_config]
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  provider = kubernetes.with_config
  metadata { name = "monitoring" }
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_namespace" "argocd" {
  provider = kubernetes.with_config
  metadata { name = "argocd" }
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_secret" "postgres_exporter_credentials" {
  provider = kubernetes.with_config
  metadata {
    name      = "postgres-exporter-credentials"
    namespace = "monitoring"
  }
  lifecycle {
    prevent_destroy = true
  }
  data = {
    password = var.rds_password
    username = var.rds_username
    endpoint = var.rds_endpoint
  }
}

# Optionally, ArgoCD Application resource here