# Stack Masters Wizard Stop Script
# Properly stops the provisioning wizard and cleans up resources

param(
    [switch]$Force = $false
)

# Color functions
function Write-Info { 
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorCustom { 
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Stack Masters Wizard Stop Script" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $PSCommandPath
$runDir = Join-Path $scriptDir "run"
$wizardDir = Join-Path $runDir "provisioning-wizard"
$pidFile = Join-Path $wizardDir "wizard.pid"

# Check for Node.js processes on port 8080
Write-Info "Looking for wizard processes..."

# Method 1: Check PID file
$pidFromFile = $null
if (Test-Path $pidFile) {
    $pidFromFile = Get-Content $pidFile -ErrorAction SilentlyContinue
    Write-Info "Found PID file: $pidFromFile"
}

# Method 2: Find Node.js processes on port 8080
$nodeProcesses = @()
$tcpConnections = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
if ($tcpConnections) {
    foreach ($conn in $tcpConnections) {
        try {
            $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($process -and $process.Name -eq "node") {
                $nodeProcesses += $process
            }
        }
        catch {
            # Ignore errors
        }
    }
}

# Method 3: Find all Node.js processes (fallback)
if ($nodeProcesses.Count -eq 0 -and $Force) {
    Write-Warning "No Node.js processes found on port 8080, checking all Node.js processes..."
    $allNodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue
    
    if ($allNodeProcesses) {
        Write-Warning "Found $($allNodeProcesses.Count) Node.js process(es)"
        $confirm = Read-Host "Stop ALL Node.js processes? This may affect other applications [y/N]"
        if ($confirm -eq 'y') {
            $nodeProcesses = $allNodeProcesses
        }
    }
}

# Stop processes
$stopped = $false
if ($nodeProcesses.Count -gt 0) {
    foreach ($proc in $nodeProcesses) {
        try {
            Write-Info "Stopping Node.js process (PID: $($proc.Id))..."
            Stop-Process -Id $proc.Id -Force
            Write-Success "Process $($proc.Id) stopped"
            $stopped = $true
        }
        catch {
            Write-ErrorCustom "Failed to stop process $($proc.Id): $($_.Exception.Message)"
        }
    }
}
elseif ($pidFromFile) {
    # Try to stop using PID from file
    try {
        $proc = Get-Process -Id $pidFromFile -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Info "Stopping process from PID file (PID: $pidFromFile)..."
            Stop-Process -Id $pidFromFile -Force
            Write-Success "Process $pidFromFile stopped"
            $stopped = $true
        }
        else {
            Write-Warning "Process $pidFromFile from PID file is not running"
        }
    }
    catch {
        Write-Warning "Could not stop process $pidFromFile"
    }
}
else {
    Write-Warning "No wizard processes found"
}

# Cleanup
Write-Info "Cleaning up wizard files..."

# Remove PID file
if (Test-Path $pidFile) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Write-Success "Removed PID file"
}

# Optional: Remove wizard directory
if ($Force -and (Test-Path $wizardDir)) {
    Write-Warning "Force flag set - removing entire wizard directory"
    try {
        # First try normal removal
        Remove-Item -Path $wizardDir -Recurse -Force -ErrorAction Stop
        Write-Success "Wizard directory removed"
    }
    catch {
        Write-Warning "Could not remove wizard directory, it may be locked"
        Write-Info "Try closing any applications using files in: $wizardDir"
    }
}

# Verify port is free
Start-Sleep -Seconds 1
$portCheck = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
if (-not $portCheck) {
    Write-Success "✅ Port 8080 is now free"
}
else {
    Write-Warning "Port 8080 is still in use"
    Write-Info "Run with -Force to stop ALL Node.js processes"
}

Write-Host ""
if ($stopped) {
    Write-Success "Wizard stopped successfully"
}
else {
    Write-Info "No wizard processes were running"
}

Write-Host ""
Write-Info "To start the wizard again, run: .\setup-windows.ps1"
Write-Info "To check wizard status, run: .\check-wizard-status.ps1"