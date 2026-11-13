<#
.SYNOPSIS
    Builds the React frontend and uploads production static assets to Amazon S3 with optimized CloudFront cache headers.
.PARAMETER BucketName
    The target private S3 bucket name.
.PARAMETER DistributionId
    Optional CloudFront Distribution ID to automatically invalidate index.html cache.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,

    [Parameter(Mandatory=$false)]
    [string]$DistributionId = "",

    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-southeast-2"
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " Building & Uploading Frontend to Amazon S3: $BucketName ($Region)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path "$scriptDir\..\..").Path
$frontendDir = Join-Path $projectRoot "frontend"
$distDir = Join-Path $frontendDir "dist"

# 1. Build Frontend
Write-Host "`n[1/4] Running production frontend build..." -ForegroundColor Yellow
Push-Location $frontendDir
try {
    npm run build
} finally {
    Pop-Location
}

if (-not (Test-Path "$distDir\index.html")) {
    Write-Error "Build output missing index.html at $distDir"
}

# 2. Upload Immutable Hashed Static Assets (CSS, JS, images)
Write-Host "`n[2/4] Uploading immutable static assets to s3://$BucketName/assets/..." -ForegroundColor Yellow
aws s3 sync "$distDir/assets" "s3://$BucketName/assets" `
    --region $Region `
    --cache-control "public, max-age=31536000, immutable" `
    --delete

# 3. Upload Root Assets (index.html, favicon, robots.txt) with Zero-Cache policy
Write-Host "`n[3/4] Uploading entrypoint index.html with no-cache policy..." -ForegroundColor Yellow
aws s3 cp "$distDir/index.html" "s3://$BucketName/index.html" `
    --region $Region `
    --cache-control "no-cache, no-store, must-revalidate" `
    --content-type "text/html"

# Upload any other root files (e.g. vite.svg, favicon)
Get-ChildItem -Path $distDir -File | Where-Object { $_.Name -ne "index.html" } | ForEach-Object {
    aws s3 cp $_.FullName "s3://$BucketName/$($_.Name)" --region $Region --cache-control "public, max-age=86400"
}

# 4. Invalidate CloudFront Cache if DistributionId is supplied
if ($DistributionId -ne "") {
    Write-Host "`n[4/4] Creating CloudFront cache invalidation for /* on distribution $DistributionId..." -ForegroundColor Yellow
    aws cloudfront create-invalidation `
        --distribution-id $DistributionId `
        --paths "/*"
} else {
    Write-Host "`n[4/4] Skipping CloudFront cache invalidation (No DistributionId passed)." -ForegroundColor Gray
}

Write-Host "`n====================================================================" -ForegroundColor Green
Write-Host " ✔ S3 Frontend Deployment Complete!" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
