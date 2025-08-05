# Build script for pre-compiling the React frontend on Windows
# This script should be run before committing to ensure the dist folder is included

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Stack Masters Provisioning Wizard Frontend Build" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Change to frontend directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Join-Path $ScriptDir "frontend"

if (-not (Test-Path $FrontendDir)) {
    Write-Host "ERROR: Frontend directory not found at $FrontendDir" -ForegroundColor Red
    exit 1
}

Set-Location $FrontendDir

# Check if Node.js is installed
$nodeVersion = $null
try {
    $nodeVersion = & node -v 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Node.js not found"
    }
} catch {
    Write-Host "ERROR: Node.js is not installed" -ForegroundColor Red
    Write-Host "Please install Node.js 18+ to build the frontend" -ForegroundColor Yellow
    exit 1
}

# Check Node version and provide compatibility info
$versionNum = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
if ($versionNum -lt 18) {
    Write-Host "ERROR: Node.js version 18+ is required (found: $nodeVersion)" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Node.js $nodeVersion detected" -ForegroundColor Green

# Provide Node.js v23 compatibility info
if ($versionNum -eq 23) {
    Write-Host "ℹ️ Node.js v23 detected - using optimized configuration for compatibility" -ForegroundColor Cyan
    Write-Host "   • Rollup WASM fallback enabled" -ForegroundColor Gray
    Write-Host "   • Tailwind CSS v3 configuration active" -ForegroundColor Gray
}

# Check for package manager
$pkgManager = $null
if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    Write-Host "✓ pnpm detected, using pnpm" -ForegroundColor Green
    $pkgManager = "pnpm"
} elseif (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "✓ npm detected, using npm" -ForegroundColor Green
    $pkgManager = "npm"
} else {
    Write-Host "ERROR: No package manager found (pnpm or npm required)" -ForegroundColor Red
    exit 1
}

# Install dependencies with compatibility options
Write-Host ""
Write-Host "Installing dependencies..." -ForegroundColor Yellow
if ($versionNum -eq 23) {
    Write-Host "Using --legacy-peer-deps for Node.js v23 compatibility" -ForegroundColor Cyan
    & $pkgManager install --legacy-peer-deps
} else {
    & $pkgManager install
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

# Run the build
Write-Host ""
Write-Host "Building production bundle..." -ForegroundColor Yellow
& $pkgManager run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed" -ForegroundColor Red
    exit 1
}

# Check if build was successful
if (-not (Test-Path "dist")) {
    Write-Host "ERROR: Build failed - dist directory not created" -ForegroundColor Red
    exit 1
}

# Show build results
Write-Host ""
Write-Host "✅ Build completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Build output:" -ForegroundColor Cyan
$distSize = (Get-ChildItem -Path "dist" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Total size: $([math]::Round($distSize, 2)) MB" -ForegroundColor Cyan
Write-Host ""
Get-ChildItem -Path "dist" | Format-Table Name, Length, LastWriteTime

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "IMPORTANT: The dist/ folder has been created." -ForegroundColor Yellow
Write-Host "Make sure to:" -ForegroundColor Yellow
Write-Host "1. Update frontend/.gitignore to NOT ignore dist/" -ForegroundColor Yellow
Write-Host "2. Commit the dist/ folder to the repository" -ForegroundColor Yellow
Write-Host "3. Test the production build locally" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow