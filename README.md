# Archive Private Repos to Azure – Automated GitHub & Azure Integration

## Overview

This solution enables you to **automatically archive all private repositories from a GitHub Organization to Azure Blob Storage**. It leverages two main GitHub Actions workflows:

1. **Deploy Terraform Storage**  
   Provisions the required Azure Storage account, blob container, and outputs their credentials as secrets/variables using Terraform.
2. **Archive Private Repos to Azure**  
   Archives all your organization's private repositories as ZIP files and uploads them to Azure Blob Storage (Archive tier).

The automation is powered by OIDC (OpenID Connect) for secure, secretless authentication between GitHub Actions and Azure, and uses a GitHub App with the correct permissions to set repository secrets and variables.

---

## Table of Contents

- [Workflows Overview](#workflows-overview)
- [Required GitHub Secrets & Variables](#required-github-secrets--variables)
- [Azure Entra ID (AAD) App Registration & OIDC Setup](#azure-entra-id-aad-app-registration--oidc-setup)
- [GitHub App Requirements](#github-app-requirements)
- [Workflow Details](#workflow-details)
- [PowerShell Script Parameters](#powershell-script-parameters)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Workflows Overview

### 1. `Deploy Terraform Storage` Workflow

- **Purpose:** Deploys Azure Storage using Terraform and sets up required secrets/variables in your repository.
- **Key Outputs:**  
  - `AZURE_STORAGE_ACCOUNT` (variable or secret)
  - `CONTAINER_NAME` (variable)
  - `AZURE_STORAGE_KEY` (secret)
- **Flexible:** Prompts user to choose between `plan`, `apply`, or `destroy` for Terraform operations.

### 2. `Archive Private Repos to Azure` Workflow

- **Purpose:** Archives all private repos to a ZIP, then uploads to Azure Blob Storage (Archive tier).
- **Runs on:** Schedule (cron, e.g., every Friday) or manually.
- **Requires:** OIDC credentials for Azure, GitHub App token for setting repo secrets/variables (on Terraform workflow), and organization name.

---

## Required GitHub Secrets & Variables

| Name                   | Type      | Set By                        | Usage                                 |
|------------------------|-----------|-------------------------------|---------------------------------------|
| `ARM_CLIENT_ID`        | Secret    | **You** (from Entra ID App)   | Azure OIDC login                      |
| `ARM_TENANT_ID`        | Secret    | **You** (from Entra ID App)   | Azure OIDC login                      |
| `ARM_SUBSCRIPTION_ID`  | Secret    | **You** (from Azure Portal)   | Azure OIDC login                      |
| `ARCHIVE_APP_ID`       | Secret    | **You** (from GitHub App)     | GitHub App for repo variable/secret mgmt |
| `ARCHIVE_APP_PRIVATE_KEY` | Secret | **You** (from GitHub App)     | GitHub App for repo variable/secret mgmt |
| `GIT_HUB_ORG`          | Variable  | **You** (repo variable)       | Your GitHub organization name         |
| `AZURE_STORAGE_ACCOUNT`| Variable  | **Terraform**                 | Storage account name                  |
| `CONTAINER_NAME`       | Variable  | **Terraform**                 | Container name                        |
| `AZURE_STORAGE_KEY`    | Secret    | **Terraform**                 | Storage account key                   |
| `GITHUB_TOKEN`         | Secret    | **GitHub**                    | For API calls (provided by platform)  |

> **Note:** `AZURE_STORAGE_ACCOUNT`, `CONTAINER_NAME`, and `AZURE_STORAGE_KEY` are automatically set by the Terraform deployment workflow.

---

## Azure Entra ID (AAD) App Registration & OIDC Setup

### 1. Register an App in Entra ID (Azure AD)

1. Go to [Azure Portal](https://portal.azure.com) > **Entra ID** > **App registrations** > **New registration**.
2. Name it (e.g., `github-azure-archive`).
3. Save the **Application (client) ID** and **Directory (tenant) ID**.  
   - Set these as `ARM_CLIENT_ID` and `ARM_TENANT_ID` in GitHub secrets.

### 2. Create Federated Credentials

1. In your app registration, go to **Certificates & secrets** > **Federated credentials** > **Add credential**.
2. Choose **GitHub Actions workflow**.
3. Fill in:
   - **Organization** and **Repository:** `your-org/your-repo`
   - **Branch:** e.g., `main` (or `*` for any branch)
   - **Environment:** Leave blank (unless you want to restrict)
4. Azure will generate a "Subject", such as  
   `repo:your-org/your-repo:ref:refs/heads/main`
5. Review and create the credential.

### 3. Assign Permissions

- Go to your Storage Account > **Access Control (IAM)**.
- Add a role assignment for your App Registration (e.g., Storage Blob Data Contributor).

---

## GitHub App Requirements

- **Why a GitHub App?**  
  The Terraform workflow uses a GitHub App for secure, auditable, and fine-grained permission to set repository secrets and variables.
- **Required Permissions:**  
  - `Administration` (read & write)
  - `Secrets` (read & write)
  - `Variables` (read & write)
- **How to configure:**  
  - [Create a GitHub App](https://github.com/settings/apps/new)
  - Generate a Private Key and note the App ID.
  - Install the App on your repository with the required permissions.
  - Add your App ID as `ARCHIVE_APP_ID` and the private key as `ARCHIVE_APP_PRIVATE_KEY` in your repository secrets.

---

## Workflow Details

### `Deploy Terraform Storage` (updated example)

```yaml
name: Deploy Terraform Storage

on:
  workflow_dispatch:
    inputs:
      action:
        description: 'Terraform action to run'
        required: true
        default: 'apply'
        type: choice
        options:
          - plan
          - apply
          - destroy

permissions:
  contents: write
  actions: write
  id-token: write

jobs:
  terraform:
    environment: production
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform
    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.5

      - name: Terraform Init (with backend Service Principal)
        run: terraform init
        env:
          ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
          ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}

      - name: Run Terraform Action
        run: |
          RESOURCE_GROUP_NAME="rg-github-archives" # must match your main.tf default or -var value!
          case "${{ github.event.inputs.action }}" in
            plan)
              terraform plan \
                -var "subscription_id=${{ secrets.ARM_SUBSCRIPTION_ID }}" \
                -var "tenant_id=${{ secrets.ARM_TENANT_ID }}" \
                -var "resource_group_name=$RESOURCE_GROUP_NAME"
              ;;
            apply)
              terraform apply -auto-approve \
                -var "subscription_id=${{ secrets.ARM_SUBSCRIPTION_ID }}" \
                -var "tenant_id=${{ secrets.ARM_TENANT_ID }}" \
                -var "resource_group_name=$RESOURCE_GROUP_NAME"
              ;;
            destroy)
              terraform destroy -auto-approve \
                -var "subscription_id=${{ secrets.ARM_SUBSCRIPTION_ID }}" \
                -var "tenant_id=${{ secrets.ARM_TENANT_ID }}" \
                -var "resource_group_name=$RESOURCE_GROUP_NAME"
              ;;
            *)
              echo "Unknown action: ${{ github.event.inputs.action }}. Use plan, apply, or destroy."
              exit 1
              ;;
          esac
        env:
          ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
          ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}

      - name: Get Terraform Outputs
        if: ${{ github.event.inputs.action == 'apply' }}
        id: tfoutputs
        run: |
          echo "account_name=$(terraform output -raw storage_account_name)" >> $GITHUB_OUTPUT
          echo "container_name=$(terraform output -raw container_name)" >> $GITHUB_OUTPUT
          echo "storage_key=$(terraform output -raw storage_account_primary_key)" >> $GITHUB_OUTPUT

      - name: Create Token
        if: ${{ github.event.inputs.action == 'apply' }}
        id: create_token
        uses: tibdex/github-app-token@v2
        with:
          app_id: ${{ secrets.ARCHIVE_APP_ID }}
          private_key: ${{ secrets.ARCHIVE_APP_PRIVATE_KEY }}

      - name: Set repo secret AZURE_STORAGE_ACCOUNT
        if: ${{ github.event.inputs.action == 'apply' }}
        run: gh secret set AZURE_STORAGE_ACCOUNT --body "${{ steps.tfoutputs.outputs.account_name }}"
        env:
          GH_TOKEN: ${{ steps.create_token.outputs.token }}

      - name: Set repo variable CONTAINER_NAME
        if: ${{ github.event.inputs.action == 'apply' }}
        run: gh variable set CONTAINER_NAME --body "${{ steps.tfoutputs.outputs.container_name }}"
        env:
          GH_TOKEN: ${{ steps.create_token.outputs.token }}

      - name: Set repo secret AZURE_STORAGE_KEY
        if: ${{ github.event.inputs.action == 'apply' }}
        run: gh secret set AZURE_STORAGE_KEY --body "${{ steps.tfoutputs.outputs.storage_key }}"
        env:
          GH_TOKEN: ${{ steps.create_token.outputs.token }}
```

### `Archive Private Repos to Azure` (unchanged)

```yaml
name: Archive Private Repos to Azure

on:
  workflow_dispatch:
  schedule:
    - cron: "0 3 * * 5"

permissions:
  contents: write
  actions: write
  id-token: write

jobs:
  archive:
    runs-on: windows-latest
    environment: production
    steps:
      - name: Checkout this repo
        uses: actions/checkout@v4
      - name: Install Az PowerShell modules
        run: |
          Install-Module -Name Az.Accounts -Force -Scope CurrentUser
          Install-Module -Name Az.Storage -Force -Scope CurrentUser
      - name: Azure Login with OIDC
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.ARM_CLIENT_ID }}
          tenant-id: ${{ secrets.ARM_TENANT_ID }}
          subscription-id: ${{ secrets.ARM_SUBSCRIPTION_ID }}
      - name: Archive selected private repos
        run: |
          pwsh ./archive-private-repos.ps1 `
            -GitHubOrg ${{ vars.GIT_HUB_ORG }} `
            -GitHubToken ${{ secrets.GITHUB_TOKEN }} `
            -StorageAccountName ${{ secrets.AZURE_STORAGE_ACCOUNT }} `
            -StorageAccountKey ${{ secrets.AZURE_STORAGE_KEY }} `
            -ContainerName ${{ vars.CONTAINER_NAME }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## PowerShell Script Parameters

```powershell
param(
    [string]$GitHubOrg = $env:GIT_HUB_ORG,
    [string]$GitHubToken,
    [string]$StorageAccountName,
    [string]$StorageAccountKey,
    [string]$ContainerName = $env:CONTAINER_NAME
)
```
- `GitHubOrg`: Organization name (from variable/secret)
- `GitHubToken`: GitHub token for API access (provided by GitHub Actions)
- `StorageAccountName`: Azure Storage account
- `StorageAccountKey`: Azure Storage account key
- `ContainerName`: Blob container

---

## How It Works

1. **Terraform workflow** provisions Azure Storage and stores key outputs as repo secrets/variables (using a GitHub App for authentication).
2. **Archive workflow** runs (scheduled or manual), authenticates to Azure with OIDC, and runs the PowerShell script to:
   - Fetch all repos in your org
   - Clone each repo and ZIP it
   - Upload each ZIP to Azure Blob Storage (Archive tier)

---

## Troubleshooting

- **OIDC Errors:**  
  - Ensure federated credential is set in Entra ID with matching subject (`repo:org/repo:ref:refs/heads/main` or wildcard).
  - All `ARM_*` secrets set and accurate.
  - `id-token: write` is set in workflow permissions.

- **Missing Variables/Secrets:**  
  - Confirm `AZURE_STORAGE_ACCOUNT`, `CONTAINER_NAME`, and `AZURE_STORAGE_KEY` are set by Terraform workflow.
  - Set `GIT_HUB_ORG` variable manually (needed for the PowerShell script).

- **GitHub App Issues:**  
  - Ensure the app is installed with correct permissions.
  - Ensure the app private key and ID are set as repository secrets.
  - App must not be suspended or removed.

- **PowerShell Script Errors:**  
  - Ensure all parameters are supplied (see workflow env/variable setup).
  - Check Azure role assignment for sufficient permissions.

---

## References

- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-cli%2Clinux)
- [Azure/login GitHub Action](https://github.com/Azure/login)
- [Terraform GitHub Provider](https://registry.terraform.io/providers/integrations/github/latest/docs)
- [GitHub: Creating and using encrypted secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [GitHub: Creating repository variables](https://docs.github.com/en/actions/learn-github-actions/variables)
- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/create-a-github-app)
