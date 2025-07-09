#!/bin/bash

echo "=== DEBUGGING EXTERNAL SECRETS OPERATOR ==="
echo

echo "1. Checking External Secrets Operator pods..."
kubectl get pods -n external-secrets-system
echo

echo "2. Checking External Secrets Operator logs..."
kubectl logs -n external-secrets-system deployment/external-secrets --tail=50
echo

echo "3. Checking if SecretStore exists..."
kubectl get secretstore -n level-up-accounts
echo

echo "4. Checking SecretStore status..."
kubectl describe secretstore aws-secrets-manager -n level-up-accounts
echo

echo "5. Checking ExternalSecret..."
kubectl get externalsecret -n level-up-accounts
echo

echo "6. Checking ExternalSecret status..."
kubectl describe externalsecret github-auth-external -n level-up-accounts
echo

echo "7. Checking if github-auth secret exists..."
kubectl get secret github-auth -n level-up-accounts
echo

echo "8. Checking github-auth secret details..."
kubectl describe secret github-auth -n level-up-accounts
echo

echo "9. Checking aws-credentials secret (for ESO)..."
kubectl get secret aws-credentials -n level-up-accounts
echo

echo "10. Testing token manually..."
TOKEN=$(kubectl get secret github-auth -n level-up-accounts -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TOKEN}"
echo "Token first 4 chars: ${TOKEN:0:4}"
echo "Testing GitHub API..."
curl -s -H "Authorization: token $TOKEN" https://api.github.com/user | head -n 5
echo

echo "=== DEBUG COMPLETE ===" 