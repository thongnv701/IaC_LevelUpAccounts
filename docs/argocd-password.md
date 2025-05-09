# Setting ArgoCD Admin Password

This guide explains how to set your own custom password for ArgoCD.

## Option 1: Use the Script to Generate Password Hash

We've provided a script that generates a bcrypt hash for your password:

1. Make the script executable:
   ```bash
   chmod +x scripts/generate_argocd_password.sh
   ```

2. Run the script with your desired password:
   ```bash
   ./scripts/generate_argocd_password.sh YourDesiredPassword
   ```

3. The script will output a bcrypt hash. Copy this hash.

4. Go to your GitHub repository Settings → Secrets and variables → Actions.

5. Create a new repository secret:
   - Name: `ARGOCD_ADMIN_PASSWORD`
   - Value: [paste the bcrypt hash here]

6. Push the changes to your repository.

## Option 2: Use Other Methods to Generate Password Hash

If you can't run the script, you can generate a bcrypt hash in other ways:

### Using Python

```bash
pip install bcrypt
python -c 'import bcrypt; import getpass; print(bcrypt.hashpw(getpass.getpass("Input password: ").encode("utf-8"), bcrypt.gensalt(rounds=10)).decode("utf-8"))'
```

### Using ArgoCD CLI

If you have the ArgoCD CLI installed:

```bash
argocd account bcrypt --password "YourDesiredPassword"
```

### Using Online Tools (For Development Only)

For non-production environments, you can use:
- [Bcrypt Generator](https://bcrypt-generator.com/)

## Fallback: Default Password

If you don't set the `ARGOCD_ADMIN_PASSWORD` secret, the system will use a default password of "admin" for development purposes. 

**Note:** For production environments, always set a secure password through the GitHub secret.

## Retrieving the Default Generated Password

If you didn't set a custom password and want to find the auto-generated one:

```bash
kubectl -n argocd get secret argocd-initial-admin-password -o jsonpath="{.data.password}" | base64 -d
``` 