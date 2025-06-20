# Archive Private Repos to Azure – Automated GitHub & Azure Integration

## Overview

This solution enables you to **automatically archive all private repositories from a GitHub Organization to Azure Blob Storage**. It leverages two main GitHub Actions workflows:

1. **Provision Remote Backend for Terraform (Required First Step)**  
   Before running Terraform to provision Azure Storage for the archives, you must first create the Azure Storage account and container that will be used as the **remote backend** for Terraform state.  
   - This backend must exist before you run any other Terraform workflow that uses remote state.
   - You can create it manually via the Azure Portal or CLI, or with a simple initial Terraform run using a local backend.  
   - After provisioning, update your `terraform` block in `main.tf` to point to the backend storage account and container.

2. **Deploy Terraform Storage**  
   Provisions the required Azure Storage account, blob container (for the actual archives), and outputs their credentials as secrets/variables using Terraform.

3. **Archive Private Repos to Azure**  
   Archives all your organization's private repositories as ZIP files and uploads them to Azure Blob Storage (Archive tier).

The automation is powered by OIDC (OpenID Connect) for secure, secretless authentication between GitHub Actions and Azure, with fallback to repository secrets/variables for storage credentials.

---

## ⚠️ Provisioning the Remote Backend for Terraform

**This must be done before running the "Deploy Terraform Storage" workflow!**

Terraform's remote backend requires an existing Azure Storage account and container to store the state file. If these resources do not exist yet, create them manually:

```sh
az storage account create --name <backendStorageAccount> --resource-group <resourceGroup> --sku Standard_LRS
az storage container create --name <backendContainer> --account-name <backendStorageAccount>
```

Then, configure your `terraform` block (in `main.tf` or equivalent):

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "<resourceGroup>"
    storage_account_name = "<backendStorageAccount>"
    container_name       = "<backendContainer>"
    key                  = "terraform.tfstate"
  }
}
```

Once the backend exists, you can safely run the `Deploy Terraform Storage` workflow to provision the storage resources for your archive solution.

---

## Table of Contents

- [Workflows Overview](#workflows-overview)
- [Required GitHub Secrets & Variables](#required-github-secrets--variables)
- [Azure Entra ID (AAD) App Registration & OIDC Setup](#azure-entra-id-aad-app-registration--oidc-setup)
- [Personal Access Token (PAT) Requirements](#personal-access-token-pat-requirements)
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

### 2. `Archive Private Repos to Azure` Workflow

- **Purpose:** Archives all private repos to a ZIP, then uploads to Azure Blob Storage (Archive tier).
- **Runs on:** Schedule (cron, e.g., every Friday) or manually.
- **Requires:** OIDC credentials for Azure, GitHub PAT for setting repo secrets/variables (on Terraform workflow), and organization name.

---

## Required GitHub Secrets & Variables

| Name                   | Type      | Set By                        | Usage                                 |
|------------------------|-----------|-------------------------------|---------------------------------------|
| `ARM_CLIENT_ID`        | Secret    | **You** (from Entra ID App)   | Azure OIDC login                      |
| `ARM_TENANT_ID`        | Secret    | **You** (from Entra ID App)   | Azure OIDC login                      |
| `ARM_SUBSCRIPTION_ID`  | Secret    | **You** (from Azure Portal)   | Azure OIDC login                      |
| `SOURCE_PAT`           | Secret    | **You** (PAT token)           | To set repo secrets/variables via Terraform workflow |
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

## Personal Access Token (PAT) Requirements

- Used in the `Deploy Terraform Storage` workflow to set repo variables/secrets via the `gh` CLI.
- **Required Scopes:**
  - `repo`
  - `admin:repo_hook`
  - `workflow`
  - `write:packages`
  - `read:org`
  - `read:user`
  - `user:email`
- [Creating a PAT](https://github.com/settings/tokens/new)
- Set as `SOURCE_PAT` secret in your repository.

---

## Workflow Details

### `Deploy Terraform Storage` (example)

```yaml
name: Deploy Terraform Storage

on:
  workflow_dispatch:

permissions:
  contents: write
  actions: write
  id-token: write

env:
  ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
  ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
  PAT_TOKEN: ${{ secrets.SOURCE_PAT }}

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
      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ env.ARM_CLIENT_ID }}
          tenant-id: ${{ env.ARM_TENANT_ID }}
          subscription-id: ${{ env.ARM_SUBSCRIPTION_ID }}
      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.5
      - name: Terraform Init
        run: terraform init
      - name: Terraform Apply
        run: |
          terraform apply -auto-approve \
            -var "subscription_id=${ARM_SUBSCRIPTION_ID}" \
            -var "tenant_id=${ARM_TENANT_ID}"
      - name: Get Terraform Outputs
        id: tfoutputs
        run: |
          echo "account_name=$(terraform output -raw storage_account_name)" >> $GITHUB_OUTPUT
          echo "container_name=$(terraform output -raw container_name)" >> $GITHUB_OUTPUT
          echo "storage_key=$(terraform output -raw storage_account_primary_key)" >> $GITHUB_OUTPUT
      - name: Set repo variable AZURE_STORAGE_ACCOUNT
        run: gh secret set AZURE_STORAGE_ACCOUNT --body "${{ steps.tfoutputs.outputs.account_name }}"
        env:
          GH_TOKEN: ${{ secrets.SOURCE_PAT }}
      - name: Set repo variable CONTAINER_NAME
        run: gh variable set CONTAINER_NAME --body "${{ steps.tfoutputs.outputs.container_name }}"
        env:
          GH_TOKEN: ${{ secrets.SOURCE_PAT }}
      - name: Set repo secret AZURE_STORAGE_KEY
        run: gh secret set AZURE_STORAGE_KEY --body "${{ steps.tfoutputs.outputs.storage_key }}"
        env:
          GH_TOKEN: ${{ secrets.SOURCE_PAT }}
```

### `Archive Private Repos to Azure` (example)

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

env:
  ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
  AZURE_STORAGE_ACCOUNT: ${{ secrets.AZURE_STORAGE_ACCOUNT }}
  AZURE_STORAGE_KEY: ${{ secrets.AZURE_STORAGE_KEY }}
  GIT_HUB_ORG: ${{ vars.GIT_HUB_ORG }}
  CONTAINER_NAME: ${{ vars.CONTAINER_NAME }}

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
          client-id: ${{ env.ARM_CLIENT_ID }}
          tenant-id: ${{ env.ARM_TENANT_ID }}
          subscription-id: ${{ env.ARM_SUBSCRIPTION_ID }}
      - name: Archive selected private repos
        run: |
          pwsh ./archive-private-repos.ps1 `
            -GitHubOrg ${{ env.GIT_HUB_ORG }} `
            -GitHubToken ${{ secrets.GITHUB_TOKEN }} `
            -StorageAccountName ${{ env.AZURE_STORAGE_ACCOUNT }} `
            -StorageAccountKey ${{ env.AZURE_STORAGE_KEY }} `
            -ContainerName ${{ env.CONTAINER_NAME }}
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

1. **Provision backend storage** for the Terraform remote backend (manual/CLI/initial run).
2. **Terraform workflow** provisions Azure Storage for archiving and stores key outputs as repo secrets/variables (using a PAT).
3. **Archive workflow** runs (scheduled or manual), authenticates to Azure with OIDC, and runs the PowerShell script to:
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

- **PAT Issues:**  
  - Ensure correct scopes.
  - PAT must not be expired or revoked.

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

---
