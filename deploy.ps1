
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+$')]
    [string]$Version
)

$ErrorActionPreference = "Stop"

# ==========================================
# CONFIGURATION
# ==========================================
$Image     = "localhost:5000/flask-app"
$Container = "registry-rollback-app"
$Port      = 8098

# ==========================================
# CHECK WHETHER CONTAINER EXISTS
# ==========================================
function Test-ContainerExists {
    $names = @(docker ps -a --format "{{.Names}}")

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check Docker containers."
    }

    return ($names -contains $Container)
}

# ==========================================
# GET CURRENT DEPLOYED VERSION
# ==========================================
function Get-PreviousVersion {
    if (-not (Test-ContainerExists)) {
        return $null
    }

    $currentImage = docker inspect --format '{{.Config.Image}}' $Container

    if ($LASTEXITCODE -ne 0 -or -not $currentImage) {
        throw "Could not identify the currently deployed image."
    }

    if ($currentImage -match ':([^:]+)$') {
        return $Matches[1]
    }

    throw "Current image tag could not be identified: $currentImage"
}

# ==========================================
# REMOVE DEMO CONTAINER IF IT EXISTS
# ==========================================
function Remove-DemoContainer {
    if (Test-ContainerExists) {
        docker rm -f $Container

        if ($LASTEXITCODE -ne 0) {
            throw "Could not remove the previous demo container."
        }
    }
}

# ==========================================
# START APPLICATION
# ==========================================
function Start-App {
    param([string]$Tag)

    Remove-DemoContainer

    Write-Host "Starting image: ${Image}:$Tag" -ForegroundColor Cyan

    docker run -d `
        --name $Container `
        --restart unless-stopped `
        -p "${Port}:80" `
        "${Image}:$Tag"

    if ($LASTEXITCODE -ne 0) {
        throw "Container startup failed for image tag $Tag."
    }

    Start-Sleep -Seconds 3
}

# ==========================================
# HEALTH CHECK
# ==========================================
function Test-AppHealth {
    param([string]$Tag)

    $html = curl.exe -s --max-time 5 "http://localhost:$Port/"

    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($html -match "Application Version $Tag")
}

# ==========================================
# DEPLOYMENT START
# ==========================================
Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host " PRIVATE REGISTRY DEPLOYMENT" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

$Previous = Get-PreviousVersion

Write-Host "Previous version : $(if ($Previous) { $Previous } else { 'None' })"
Write-Host "Target version   : $Version"
Write-Host ""

# Pull image before disturbing the running container
Write-Host "Pulling image from private registry..." -ForegroundColor Cyan

docker pull "${Image}:$Version"

if ($LASTEXITCODE -ne 0) {
    throw "Image pull failed. Existing deployment has not been changed."
}

# ==========================================
# DEPLOY TARGET VERSION
# ==========================================
try {
    Start-App -Tag $Version

    if (Test-AppHealth -Tag $Version) {
        Write-Host ""
        Write-Host "DEPLOYMENT SUCCESS: $Version" -ForegroundColor Green
        Write-Host "URL: http://localhost:$Port"
        exit 0
    }

    Write-Host "Health check failed for $Version." -ForegroundColor Yellow
}
catch {
    Write-Host "Deployment error: $_" -ForegroundColor Red
}

# ==========================================
# AUTOMATIC ROLLBACK
# ==========================================
Write-Host ""
Write-Host "Deployment failed. Starting rollback..." -ForegroundColor Yellow

if (-not $Previous) {
    Remove-DemoContainer
    throw "No previous version is available. Rollback cannot be performed."
}

try {
    Start-App -Tag $Previous

    if (Test-AppHealth -Tag $Previous) {
        Write-Host ""
        Write-Host "ROLLBACK SUCCESS: Restored $Previous" -ForegroundColor Green
        Write-Host "URL: http://localhost:$Port"
        exit 1
    }
}
catch {
    Write-Host "Rollback error: $_" -ForegroundColor Red
}

throw "CRITICAL: Rollback failed. Check Docker container status."
