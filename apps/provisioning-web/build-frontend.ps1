# Stack Masters Frontend Build Script for Windows
# Handles Node.js v23 compatibility issues automatically

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Stack Masters Frontend Build (Windows)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get Node.js version
$nodeVersion = & node --version 2>&1
Write-Host "Node.js version: $nodeVersion" -ForegroundColor Yellow

# Check if we're on Node.js v23
$isNodeV23 = $false
if ($nodeVersion -match "v23\.") {
    $isNodeV23 = $true
    Write-Host "Detected Node.js v23 - Using compatibility mode" -ForegroundColor Yellow
}

# Navigate to frontend directory
$scriptDir = Split-Path -Parent $PSCommandPath
$frontendDir = Join-Path $scriptDir "frontend"

if (-not (Test-Path $frontendDir)) {
    Write-Host "[ERROR] Frontend directory not found: $frontendDir" -ForegroundColor Red
    exit 1
}

Set-Location $frontendDir

# Clean install if needed
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    
    # Set npm to use local cache to avoid permission issues
    $env:npm_config_cache = "$frontendDir\.npm-cache"
    if (-not (Test-Path $env:npm_config_cache)) {
        New-Item -Path $env:npm_config_cache -ItemType Directory -Force | Out-Null
    }
    
    # Always use --legacy-peer-deps due to date-fns version conflict
    Write-Host "Using --legacy-peer-deps for dependency compatibility" -ForegroundColor Yellow
    & npm install --legacy-peer-deps --cache $env:npm_config_cache
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install dependencies" -ForegroundColor Red
        exit 1
    }
}

# Build the frontend
Write-Host ""
Write-Host "Building React frontend..." -ForegroundColor Cyan

try {
    & npm run build
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCESS] Frontend built successfully!" -ForegroundColor Green
        Write-Host "Build output: $frontendDir\dist" -ForegroundColor Green
        
        # Copy to backend if needed
        $backendDistDir = Join-Path $scriptDir "backend\frontend\dist"
        $parentDir = Split-Path -Parent $backendDistDir
        
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Host "Copying build to backend directory..." -ForegroundColor Cyan
        Copy-Item -Path "dist" -Destination $backendDistDir -Recurse -Force
        Write-Host "[SUCCESS] Frontend deployed to backend!" -ForegroundColor Green
    }
    else {
        throw "Build failed with exit code $LASTEXITCODE"
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Build failed!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    
    if ($isNodeV23) {
        Write-Host ""
        Write-Host "Node.js v23 Compatibility Note:" -ForegroundColor Yellow
        Write-Host "The build uses @rollup/wasm-node for cross-platform compatibility." -ForegroundColor Yellow
        Write-Host "If issues persist, consider using Node.js v20 LTS." -ForegroundColor Yellow
    }
    
    exit 1
}