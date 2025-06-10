#!/bin/bash

# Ensure terraform outputs are available
echo "⏳ Extracting Terraform outputs..."
storage_account_name=$(terraform output -raw storage_account_name)
storage_account_key=$(terraform output -raw storage_account_primary_key)
container_name=$(terraform output -raw container_name)

# Confirm values
echo "📦 Storage Account: $storage_account_name"
echo "🔐 Setting secrets..."

# Set GitHub secrets using gh CLI
gh secret set AZURE_STORAGE_ACCOUNT --body "$storage_account_name"
gh secret set AZURE_STORAGE_KEY --body "$storage_account_key"
gh secret set AZURE_CONTAINER_NAME --body "$container_name"

echo "✅ GitHub secrets set successfully!"
