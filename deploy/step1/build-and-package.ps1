<#
.SYNOPSIS
    Builds the frontend production bundle and packages backend, frontend,
    and Step 1 deployment scripts into deploy.zip for AWS EC2.

.DESCRIPTION
    Step 1 Single-Server Packaging Script.
    - Runs 'npm run build' inside frontend/
    - Creates a staging directory with:
        * backend/ (excluding .env, venv, __pycache__, .pytest_cache, sqlite db)
        * frontend/dist/
        * deploy/step1/ (setup-server.sh, nginx.conf, api.service)
    - Strictly excludes secrets (*.pem, *.key, .env), node_modules, and venv
    - Compresses into deploy.zip at repository root
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$ZipPath = Join-Path $RepoRoot "deploy.zip"

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " Packaging Step 1 Single-Server Deployment Bundle" -ForegroundColor Cyan
Write-Host " Repo Root: $RepoRoot" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Verify Prerequisites
# ------------------------------------------------------------------------------
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] Node.js/npm is required to build the frontend. Please ensure npm is in your PATH."
    exit 1
}

# ------------------------------------------------------------------------------
# 2. Build Frontend Production Static Bundle
# ------------------------------------------------------------------------------
Write-Host "`n[1/4] Building React frontend static assets..." -ForegroundColor Yellow
$FrontendDir = Join-Path $RepoRoot "frontend"

Push-Location $FrontendDir
try {
    npm run build
    if ($LASTEXITCODE -ne 0) {
        throw "npm run build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$FrontendDist = Join-Path $FrontendDir "dist"
if (-not (Test-Path (Join-Path $FrontendDist "index.html"))) {
    Write-Error "[ERROR] Frontend build did not produce $FrontendDist\index.html"
    exit 1
}
Write-Host "[OK] Frontend build completed successfully." -ForegroundColor Green

# ------------------------------------------------------------------------------
# 3. Assemble Clean Staging Directory
# ------------------------------------------------------------------------------
Write-Host "`n[2/4] Assembling files in clean staging directory..." -ForegroundColor Yellow
$StagingGuid = [System.Guid]::NewGuid().ToString("N")
$StagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "notes_deploy_$StagingGuid"

try {
    $StagingBackend = Join-Path $StagingDir "backend"
    $StagingFrontend = Join-Path $StagingDir "frontend\dist"
    $StagingDeploy = Join-Path $StagingDir "deploy\step1"

    New-Item -ItemType Directory -Path $StagingBackend -Force | Out-Null
    New-Item -ItemType Directory -Path $StagingFrontend -Force | Out-Null
    New-Item -ItemType Directory -Path $StagingDeploy -Force | Out-Null

    # Define exclusion sets for backend files and directories
    $ExcludedDirNames = @("venv", ".venv", "env", "__pycache__", ".pytest_cache", "node_modules", ".git", ".coverage", "htmlcov")
    $ExcludedExtensions = @(".pyc", ".pyo", ".pyd", ".sqlite3", ".db", ".pem", ".key", ".cert", ".log", ".swp", ".swo", ".tmp")

    # Copy backend source tree
    $BackendSrc = Join-Path $RepoRoot "backend"
    Get-ChildItem -Path $BackendSrc -Recurse | ForEach-Object {
        $item = $_
        $relPath = $item.FullName.Substring($BackendSrc.Length).TrimStart('\', '/')

        # Check if item or any parent is in excluded directory names
        $parts = $relPath.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $matchesExcludedDir = $false
        foreach ($part in $parts) {
            if ($ExcludedDirNames -contains $part) {
                $matchesExcludedDir = $true
                break
            }
        }
        if ($matchesExcludedDir) { return }

        # Check if file starts with .env or matches key/pem/cert
        if ($item.Name -like ".env*" -or $item.Name -like "*.pem" -or $item.Name -like "*.key" -or $item.Name -like "*.cert") {
            return
        }

        # Check excluded extension
        if (-not $item.PSIsContainer -and ($ExcludedExtensions -contains $item.Extension)) {
            return
        }

        $destPath = Join-Path $StagingBackend $relPath
        if ($item.PSIsContainer) {
            if (-not (Test-Path $destPath)) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
            }
        } else {
            $destParent = Split-Path -Parent $destPath
            if (-not (Test-Path $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -Path $item.FullName -Destination $destPath -Force
        }
    }
    Write-Host "[OK] Backend files staged (excluding venv, .env, __pycache__, secrets)." -ForegroundColor Green

    # Copy frontend/dist
    Get-ChildItem -Path $FrontendDist -Recurse | ForEach-Object {
        $item = $_
        $relPath = $item.FullName.Substring($FrontendDist.Length).TrimStart('\', '/')
        $destPath = Join-Path $StagingFrontend $relPath

        if ($item.PSIsContainer) {
            if (-not (Test-Path $destPath)) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
            }
        } else {
            $destParent = Split-Path -Parent $destPath
            if (-not (Test-Path $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -Path $item.FullName -Destination $destPath -Force
        }
    }
    Write-Host "[OK] Frontend dist assets staged." -ForegroundColor Green

    # Copy deploy/step1 scripts and templates
    $Step1Src = Join-Path $RepoRoot "deploy\step1"
    Copy-Item -Path (Join-Path $Step1Src "setup-server.sh") -Destination $StagingDeploy -Force
    Copy-Item -Path (Join-Path $Step1Src "nginx.conf") -Destination $StagingDeploy -Force
    Copy-Item -Path (Join-Path $Step1Src "api.service") -Destination $StagingDeploy -Force
    Write-Host "[OK] Deploy scripts and service configs staged." -ForegroundColor Green

    # --------------------------------------------------------------------------
    # 4. Create deploy.zip Archive
    # --------------------------------------------------------------------------
    Write-Host "`n[3/4] Compressing staging directory into deploy.zip..." -ForegroundColor Yellow
    if (Test-Path $ZipPath) {
        Remove-Item -Path $ZipPath -Force
    }

    Compress-Archive -Path "$StagingDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host "[OK] Archive generated: $ZipPath" -ForegroundColor Green

    # --------------------------------------------------------------------------
    # 5. Verify Archive Content
    # --------------------------------------------------------------------------
    Write-Host "`n[4/4] Verifying archive..." -ForegroundColor Yellow
    $ZipItem = Get-Item $ZipPath
    $ZipSizeKB = [math]::Round($ZipItem.Length / 1KB, 2)
    $ZipSizeMB = [math]::Round($ZipItem.Length / 1MB, 2)

    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " Package Created Successfully!" -ForegroundColor Green
    Write-Host (" Location: {0}" -f $ZipPath) -ForegroundColor White
    Write-Host (" Size:     {0} KB ({1} MB)" -f $ZipSizeKB, $ZipSizeMB) -ForegroundColor White
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "`nNext steps to deploy to your Amazon Linux 2023 EC2 instance:" -ForegroundColor White
    Write-Host "  1. scp -i <your-key.pem> deploy.zip ec2-user@<EC2_PUBLIC_IP>:~/" -ForegroundColor Yellow
    Write-Host "  2. ssh -i <your-key.pem> ec2-user@<EC2_PUBLIC_IP>" -ForegroundColor Yellow
    Write-Host "  3. unzip deploy.zip" -ForegroundColor Yellow
    Write-Host "  4. chmod +x deploy/step1/setup-server.sh" -ForegroundColor Yellow
    Write-Host "  5. sudo ./deploy/step1/setup-server.sh" -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Cyan
} finally {
    if (Test-Path $StagingDir) {
        Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
