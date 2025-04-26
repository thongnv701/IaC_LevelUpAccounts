# My k3s Cluster Repository

This repository contains configurations and scripts for deploying a lightweight k3s cluster on AWS with the following components:
- Prometheus
- Grafana
- Loki
- Argo CD
- Postgres Exporter

## Prerequisites
- AWS account with Free Tier access
- kubectl, Helm, and Terraform installed
- SSH key configured for EC2 instances

## Setup Instructions
1. Clone this repository.
2. Configure AWS credentials.
3. Run `terraform apply` to provision infrastructure.
4. Use `scripts/deploy.sh` to deploy Helm charts.