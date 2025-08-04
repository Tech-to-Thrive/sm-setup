# Stack Masters Wizard Status Checker
# This script checks if the provisioning wizard is running and provides diagnostics

param(
    [switch]$Detailed = $false,
    [switch]$Fix = $false
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
Write-Host "   Stack Masters Wizard Status Checker" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if port 8080 is in use
Write-Info "Checking port 8080..."
$tcpConnections = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

if ($tcpConnections) {
    Write-Success "Port 8080 is in use"
    
    # Try to identify the process
    foreach ($conn in $tcpConnections) {
        try {
            $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            Write-Info "Process: $($process.Name) (PID: $($process.Id))"
            
            # Check if it's Node.js
            if ($process.Name -eq "node") {
                Write-Success "Node.js process found on port 8080"
                
                # Try to access the wizard
                Write-Info "Testing wizard connectivity..."
                try {
                    $response = Invoke-WebRequest -Uri "http://localhost:8080" -TimeoutSec 5 -UseBasicParsing
                    if ($response.StatusCode -eq 200) {
                        Write-Success "✅ Wizard is running and accessible at http://localhost:8080"
                    }
                }
                catch {
                    if ($_.Exception.Response.StatusCode -eq 401 -or $_.Exception.Response.StatusCode -eq 403) {
                        Write-Success "✅ Wizard is running (authentication required)"
                        Write-Info "Access the wizard at: http://localhost:8080"
                    }
                    else {
                        Write-Warning "Wizard may be starting up or experiencing issues"
                        Write-Info "Error: $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-Warning "Port 8080 is in use by $($process.Name), not the Stack Masters wizard"
                if ($Fix) {
                    Write-Info "Use -Fix to attempt to stop this process and free the port"
                    $confirm = Read-Host "Stop process $($process.Name) (PID: $($process.Id))? [y/N]"
                    if ($confirm -eq 'y') {
                        Stop-Process -Id $process.Id -Force
                        Write-Success "Process stopped"
                    }
                }
            }
        }
        catch {
            Write-ErrorCustom "Could not identify process on port 8080"
        }
    }
}
else {
    Write-ErrorCustom "❌ Nothing is listening on port 8080"
    Write-Info "The wizard is not running"
    
    if ($Fix) {
        Write-Info "Attempting to start the wizard..."
        $runDir = Join-Path $PSScriptRoot "run\provisioning-wizard"
        if (Test-Path $runDir) {
            Write-Info "Found wizard directory: $runDir"
            & "$PSScriptRoot\setup-windows.ps1"
        }
        else {
            Write-ErrorCustom "Wizard not set up. Please run setup-windows.ps1 first"
        }
    }
    else {
        Write-Info "Run .\setup-windows.ps1 to start the wizard"
    }
}

# Detailed diagnostics
if ($Detailed) {
    Write-Host ""
    Write-Info "=== Detailed Diagnostics ==="
    
    # Check Node.js
    Write-Info "Node.js version:"
    if (Get-Command node -ErrorAction SilentlyContinue) {
        & node --version
    }
    else {
        Write-ErrorCustom "Node.js not found"
    }
    
    # Check wizard directory
    $wizardDir = Join-Path $PSScriptRoot "run\provisioning-wizard"
    Write-Info "Wizard directory: $wizardDir"
    if (Test-Path $wizardDir) {
        Write-Success "Wizard directory exists"
        
        # Check for PID file
        $pidFile = Join-Path $wizardDir "wizard.pid"
        if (Test-Path $pidFile) {
            $pid = Get-Content $pidFile
            Write-Info "Last known PID: $pid"
            
            $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($process) {
                Write-Success "Process $pid is still running"
            }
            else {
                Write-Warning "Process $pid is not running"
            }
        }
    }
    else {
        Write-ErrorCustom "Wizard directory not found"
    }
    
    # Check recent logs
    $logsDir = Join-Path $PSScriptRoot "logs"
    if (Test-Path $logsDir) {
        Write-Info "Recent log files:"
        Get-ChildItem $logsDir -Filter "*.log" | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First 5 | 
            ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    
    # Network information
    Write-Host ""
    Write-Info "Network interfaces:"
    Get-NetIPAddress -AddressFamily IPv4 | 
        Where-Object { $_.IPAddress -ne "127.0.0.1" } | 
        ForEach-Object { Write-Host "  $($_.IPAddress) ($($_.InterfaceAlias))" -ForegroundColor Gray }
}

Write-Host ""
Write-Info "Use -Detailed for more diagnostics"
Write-Info "Use -Fix to attempt automatic fixes"