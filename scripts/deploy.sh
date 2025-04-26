#!/bin/bash

# Deploy Helm charts
echo "Deploying Prometheus..."
helm install prometheus ./helm/prometheus -n monitoring --create-namespace

echo "Deploying Loki + Grafana..."
helm install loki ./helm/loki -n monitoring

echo "Deploying Argo CD..."
helm install argocd ./helm/argocd -n argocd --create-namespace

echo "Deploying Postgres Exporter..."
helm install postgres-exporter ./helm/postgres-exporter -n monitoring

echo "All services deployed successfully."