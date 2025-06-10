param(
    [string]$GitHubOrg = "SONE-WorkshopPoligon",
    [string]$GitHubToken,
    [string]$StorageAccountName,
    [string]$StorageAccountKey,
    [string]$ContainerName = "security-backups"
)

Import-Module Az.Accounts -Force
Import-Module Az.Storage -Force

# Azure Storage context
$connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$StorageAccountKey;EndpointSuffix=core.windows.net"
$ctx = New-AzStorageContext -ConnectionString $connectionString

# GitHub API headers
$headers = @{ Authorization = "token $GitHubToken" }

# Get all repos from the organization
$page = 1
$repos = @()

do {
    $response = Invoke-RestMethod -Uri "https://api.github.com/orgs/$GitHubOrg/repos?per_page=100&page=$page" -Headers $headers
    $repos += $response
    $page++
} while ($response.Count -gt 0)

Write-Host "Found $($repos.Count) repositories."

foreach ($repo in $repos) {
    $repoName = $repo.name
    $cloneUrl = $repo.clone_url
    $safeName = $repoName -replace '[^a-zA-Z0-9\-]', '_'
    $tempDir = Join-Path $env:RUNNER_TEMP $safeName
    $zipPath = "$env:RUNNER_TEMP\$safeName.zip"

    Write-Host "`n==> Cloning: $repoName"
    git clone --depth 1 "https://x-access-token:$GitHubToken@github.com/$GitHubOrg/$repoName.git" $tempDir

    if (-Not (Test-Path -Path $tempDir)) {
        Write-Host "❌ Failed to clone $repoName. Skipping."
        continue
    }

    Write-Host "✅ Cloned $repoName. Creating ZIP..."
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath)

    Write-Host "📤 Uploading $safeName.zip to Azure Blob (Archive tier)..."
    Set-AzStorageBlobContent -File $zipPath `
                             -Container $ContainerName `
                             -Blob "$safeName-$(Get-Date -Format yyyyMMdd-HHmmss).zip" `
                             -Context $ctx `
                             -StandardBlobTier "Archive" `
                             -Force
}
