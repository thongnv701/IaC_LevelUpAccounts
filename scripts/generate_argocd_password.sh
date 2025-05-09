#!/bin/bash

# Check if a password was provided as an argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <password>"
  echo "Please provide a password as an argument"
  exit 1
fi

# Store the password from the first argument
PASSWORD=$1

# Install htpasswd if it's not already installed
if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd is not installed. Trying to install it..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y apache2-utils
  elif command -v yum &> /dev/null; then
    sudo yum install -y httpd-tools
  elif command -v brew &> /dev/null; then
    brew install httpd
  else
    echo "Could not install htpasswd. Please install apache2-utils manually."
    exit 1
  fi
fi

# Generate bcrypt hash
HASH=$(htpasswd -bnBC 10 "" $PASSWORD | tr -d ':\n')

# Remove the first two characters (htpasswd adds a leading ':', which we don't want)
HASH=${HASH:2}

echo "Your bcrypt hash for '$PASSWORD' is:"
echo "$HASH"
echo ""
echo "To use this in GitHub Actions, create a secret named ARGOCD_ADMIN_PASSWORD with this value."
echo "To test this is working correctly after deployment, try logging in to ArgoCD with:"
echo "Username: admin"
echo "Password: $PASSWORD" 