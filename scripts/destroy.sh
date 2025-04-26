#!/bin/bash

# Delete Helm releases
echo "Deleting Prometheus..."
helm uninstall prometheus -n monitoring

echo "Deleting Loki + Grafana..."
helm uninstall loki -n monitoring

echo "Deleting Argo CD..."
helm uninstall argocd -n argocd

echo "Deleting Postgres Exporter..."
helm uninstall postgres-exporter -n monitoring

echo "All services deleted successfully."