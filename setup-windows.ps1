# Stack Masters Windows Server Setup Script
# PowerShell script for preparing Windows Server for containerized Stack Masters deployment

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoUrl = "",
    
    [Parameter()]
    [switch]$SkipFirewall = $false,
    
    [Parameter()]
    [switch]$SkipAuth = $false,
    
    [Parameter()]
    [switch]$Server = $false,
    
    [Parameter()]
    [switch]$Local = $false,
    
    [Parameter()]
    [switch]$Development = $false,
    
    [Parameter()]
    [switch]$Help = $false,
    
    [Parameter()]
    [ValidateSet('server', 'local', 'Server', 'Local', 'SERVER', 'LOCAL', IgnoreCase = $true)]
    [string]$Mode = ""
)

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script version
$VERSION = "1.0.0"

# Color functions for PowerShell
function Write-Info { 
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogFile -Value "[$timestamp] INFO: $Message"
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogFile -Value "[$timestamp] SUCCESS: $Message"
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogFile -Value "[$timestamp] WARNING: $Message"
}

function Write-ErrorCustom { 
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogFile -Value "[$timestamp] ERROR: $Message"
}

# Initialize logging in logs directory
$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrEmpty($scriptDir)) {
    # Fallback for when running interactively
    $scriptDir = (Get-Location).Path
}

# Create logs directory if it doesn't exist
$logsDir = Join-Path $scriptDir "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
}

# Create timestamped log filename
$logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $logsDir "stack-masters-setup-$logTimestamp.log"

# Write log header
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $script:LogFile -Value "================================================"
Add-Content -Path $script:LogFile -Value "Stack Masters Setup Script - Started at $timestamp"
Add-Content -Path $script:LogFile -Value "================================================"

function Show-Help {
    $helpText = @"
Stack Masters Windows Setup Script v$VERSION

USAGE:
    .\setup-windows.ps1 [OPTIONS]

OPTIONS:
    -Mode <string>       Deployment mode: 'server' or 'local' (case-insensitive)
    -Server              Server deployment mode (configures firewall)
    -Local               Local development mode (skips firewall)
    -Development         Alias for -Local
    -RepoUrl <string>    GitHub repository URL to clone
    -SkipFirewall        Skip Windows Firewall configuration
    -SkipAuth            Skip GitHub authentication (for testing)
    -Help                Show this help message

EXAMPLES:
    .\setup-windows.ps1 -Mode server    # Force server mode
    .\setup-windows.ps1 -Local          # Force local mode
    .\setup-windows.ps1                 # Auto-detect based on OS type
    .\setup-windows.ps1 -RepoUrl "https://github.com/AI-Stack-Masters/stack-community"
    .\setup-windows.ps1 -RepoUrl "https://github.com/AI-Stack-Master-Pros/stack-pro"

AUTOMATIC BEHAVIOR:
    - Windows Server: Configures firewall for server deployment
    - Windows 10/11: Skips firewall configuration (local development)
    - Use -Server or -Local flags to override automatic detection

This script will install:
- Git for Windows (via winget)
- Docker Desktop (via winget)
- GitHub CLI (via winget)
- Configure Windows Firewall (server mode only)
- Clone the specified repository

Requirements:
- Windows 10 1809+, Windows 11, or Windows Server 2019+
- Windows Package Manager (winget)
- Administrator privileges
- Skool community membership for repository access:
  * AI Stack Masters (Free): https://www.skool.com/ai-stack-masters
  * AI Stack Master Pros (Paid): https://www.skool.com/ai-stack-master-pros
"@
    Write-Host $helpText
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsType {
    # Get OS information
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    
    # ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
    if ($os.ProductType -eq 1) {
        # Desktop OS (Windows 10/11)
        return @{
            Type = "Desktop"
            Name = $os.Caption
            Version = $os.Version
            IsServer = $false
        }
    }
    else {
        # Server OS
        return @{
            Type = "Server"
            Name = $os.Caption
            Version = $os.Version
            IsServer = $true
        }
    }
}

function Update-Path {
    # Refresh PATH environment variable to include newly installed programs
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
    
    # Also refresh from registry for immediate effect
    $registryPath = 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment'
    $envPath = (Get-ItemProperty -Path $registryPath -Name PATH).Path
    $env:PATH = "$envPath;$userPath"
}

function Stop-ExistingWizard {
    Write-Info "Checking for existing wizard processes..."
    
    $cleanupPerformed = $false
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptDir)) {
        $scriptDir = (Get-Location).Path
    }
    
    # Method 1: Kill ALL processes on port 58217 (our unique wizard port)
    Write-Info "Checking port 58217..."
    try {
        $tcpConnections = Get-NetTCPConnection -LocalPort 58217 -State Listen -ErrorAction SilentlyContinue
        if ($tcpConnections) {
            Write-Warning "Found $($tcpConnections.Count) process(es) using port 58217. Force stopping all..."
            foreach ($conn in $tcpConnections) {
                try {
                    Write-Info "Force stopping process on port 58217 (PID: $($conn.OwningProcess))..."
                    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                    $cleanupPerformed = $true
                }
                catch {
                    # Use taskkill as fallback
                    & taskkill /F /PID $conn.OwningProcess 2>$null
                }
            }
            Start-Sleep -Seconds 3
        }
    }
    catch {
        # Fallback: use netstat and taskkill
        Write-Info "Using netstat fallback to check port 58217..."
        $netstatOutput = & netstat -ano | findstr ":58217.*LISTENING"
        if ($netstatOutput) {
            $netstatOutput | ForEach-Object {
                if ($_ -match '\s+(\d+)$') {
                    $pid = $matches[1]
                    Write-Info "Force stopping process on port 58217 (PID: $pid)..."
                    & taskkill /F /PID $pid 2>$null
                    $cleanupPerformed = $true
                }
            }
            Start-Sleep -Seconds 3
        }
    }
    
    # Method 2: Check for PID file
    $pidFile = Join-Path $scriptDir "run\provisioning-wizard\wizard.pid"
    if (Test-Path $pidFile) {
        try {
            $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
            if ($pid) {
                Write-Info "Found PID file. Force stopping process (PID: $pid)..."
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                & taskkill /F /PID $pid 2>$null
                $cleanupPerformed = $true
            }
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore errors
        }
    }
    
    # Method 3: Kill ALL node processes that might be ours
    Write-Info "Checking for Node.js processes..."
    $nodeProcesses = @(Get-Process -Name "node" -ErrorAction SilentlyContinue)
    if ($nodeProcesses.Count -gt 0) {
        Write-Warning "Found $($nodeProcesses.Count) Node.js process(es). Checking which are wizard processes..."
        
        $wizardDir = Join-Path $scriptDir "run\provisioning-wizard"
        foreach ($proc in $nodeProcesses) {
            try {
                # Get full command line
                $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($wmiProc) {
                    $cmdLine = $wmiProc.CommandLine
                    # Check if it's our wizard process
                    if ($cmdLine -like "*provisioning-wizard*" -or 
                        $cmdLine -like "*server-integrated.js*" -or
                        $cmdLine -like "*$wizardDir*") {
                        Write-Info "Force stopping wizard Node.js process (PID: $($proc.Id))..."
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        & taskkill /F /PID $proc.Id 2>$null
                        $cleanupPerformed = $true
                    }
                }
            }
            catch {
                # If we can't check, kill it if it's using our port
                try {
                    $tcpCheck = Get-NetTCPConnection -OwningProcess $proc.Id -LocalPort 58217 -ErrorAction SilentlyContinue
                    if ($tcpCheck) {
                        Write-Info "Force stopping Node.js process on port 58217 (PID: $($proc.Id))..."
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        & taskkill /F /PID $proc.Id 2>$null
                        $cleanupPerformed = $true
                    }
                }
                catch {
                    # Ignore
                }
            }
        }
    }
    
    # Method 4: Use handle.exe or PowerShell to find processes locking our directory
    $wizardDir = Join-Path $scriptDir "run\provisioning-wizard"
    if (Test-Path $wizardDir) {
        Write-Info "Checking for processes locking wizard directory..."
        
        # Try PowerShell method to find locking processes
        try {
            # This finds processes that have modules loaded from our directory
            Get-Process | Where-Object {
                try {
                    $modules = $_ | Select-Object -ExpandProperty Modules -ErrorAction SilentlyContinue
                    $modules | Where-Object { $_.FileName -like "*$wizardDir*" }
                } catch { $false }
            } | ForEach-Object {
                Write-Info "Force stopping process with modules in wizard directory: $($_.Name) (PID: $($_.Id))..."
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                & taskkill /F /PID $_.Id 2>$null
                $cleanupPerformed = $true
            }
        }
        catch {
            # Ignore errors
        }
    }
    
    if ($cleanupPerformed) {
        Write-Success "Aggressive cleanup completed. Waiting for processes to fully terminate..."
        Start-Sleep -Seconds 5  # Give more time for processes to die
        
        # Double-check port is free
        $portCheck = Get-NetTCPConnection -LocalPort 58217 -State Listen -ErrorAction SilentlyContinue
        if (-not $portCheck) {
            Write-Success "Port 58217 is now available ✓"
        }
        else {
            Write-Warning "Port 58217 is STILL in use. Attempting final cleanup..."
            # Last resort - kill anything on port 58217
            $portCheck | ForEach-Object {
                & taskkill /F /PID $_.OwningProcess 2>$null
            }
            Start-Sleep -Seconds 2
        }
    }
    else {
        Write-Success "No existing wizard processes found ✓"
    }
    
    # Final cleanup - remove any stale PID files
    $pidFiles = @(
        (Join-Path $scriptDir "run\provisioning-wizard\wizard.pid"),
        (Join-Path $scriptDir "run\provisioning-wizard\backend\wizard.pid")
    )
    foreach ($file in $pidFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
}

function Check-SystemPackages {
    Write-Info "Checking system packages..."
    Write-Host ""
    
    $packageStatus = @{
        Git = $false
        GitHubCLI = $false
        Docker = $false
        Winget = $false
    }
    
    $installedPackages = @()
    $missingPackages = @()
    
    # Check Winget
    Write-Info "Checking Windows Package Manager (winget)..."
    try {
        $wingetVersion = & winget --version 2>&1
        if ($?) {
            $packageStatus.Winget = $true
            $installedPackages += "✓ Windows Package Manager (winget) - $wingetVersion"
        }
    }
    catch {
        $missingPackages += "✗ Windows Package Manager (winget) - Required for installations"
    }
    
    # Check Git
    Write-Info "Checking Git..."
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = & git --version 2>&1
        $packageStatus.Git = $true
        $installedPackages += "✓ Git - $gitVersion"
    }
    else {
        $missingPackages += "✗ Git - Version control system"
    }
    
    # Check GitHub CLI
    Write-Info "Checking GitHub CLI..."
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVersion = & gh --version 2>&1 | Select-Object -First 1
        $packageStatus.GitHubCLI = $true
        $installedPackages += "✓ GitHub CLI - $ghVersion"
    }
    else {
        $missingPackages += "✗ GitHub CLI - Required for repository authentication"
    }
    
    # Check Docker
    Write-Info "Checking Docker..."
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = & docker --version 2>&1
        $packageStatus.Docker = $true
        $installedPackages += "✓ Docker - $dockerVersion"
    }
    else {
        $missingPackages += "✗ Docker Desktop - Container runtime"
    }
    
    # Display results
    Write-Host ""
    Write-Host "System Package Status:" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
    
    if ($installedPackages.Count -gt 0) {
        Write-Host ""
        Write-Host "Installed packages:" -ForegroundColor Green
        foreach ($package in $installedPackages) {
            Write-Host "  $package" -ForegroundColor Green
        }
    }
    
    if ($missingPackages.Count -gt 0) {
        Write-Host ""
        Write-Host "Missing packages:" -ForegroundColor Yellow
        foreach ($package in $missingPackages) {
            Write-Host "  $package" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    return $packageStatus
}

function Confirm-Installation {
    param(
        [hashtable]$PackageStatus
    )
    
    $needsInstallation = $false
    $installList = @()
    
    if (-not $PackageStatus.Winget) {
        Write-ErrorCustom "Windows Package Manager (winget) is required but not available"
        Write-Info "Please ensure you have:"
        Write-Info "- Windows 10 version 1809 or later"
        Write-Info "- Windows Server 2019 or later"
        Write-Info "- Or install App Installer from Microsoft Store"
        throw "Cannot proceed without winget"
    }
    
    if (-not $PackageStatus.Git) {
        $needsInstallation = $true
        $installList += "- Git for Windows"
    }
    
    if (-not $PackageStatus.GitHubCLI) {
        $needsInstallation = $true
        $installList += "- GitHub CLI"
    }
    
    if (-not $PackageStatus.Docker) {
        $needsInstallation = $true
        $installList += "- Docker Desktop"
    }
    
    if (-not $needsInstallation) {
        Write-Success "All required packages are already installed!"
        return $true
    }
    
    Write-Host ""
    Write-Host "The following packages will be installed:" -ForegroundColor Yellow
    foreach ($item in $installList) {
        Write-Host "  $item" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Do you want to proceed with the installation? (Y/N) " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -match '^[Yy](es)?$') {
        Write-Host ""
        Write-Info "Proceeding with installation..."
        return $true
    }
    else {
        Write-Warning "Installation cancelled by user"
        return $false
    }
}


function Install-Git {
    Write-Info "Installing Git for Windows..."
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = & git --version
        Write-Info "Git already installed: $gitVersion"
        return
    }
    
    try {
        Write-Info "Installing Git via winget..."
        $result = & winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Winget install failed with exit code: $LASTEXITCODE"
        }
        
        # Refresh PATH
        Update-Path
        
        # Verify installation
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Success "Git installed successfully"
        } else {
            throw "Git installation completed but git command not found in PATH"
        }
    }
    catch {
        Write-ErrorCustom "Failed to install Git: $($_.Exception.Message)"
        throw "Failed to install Git: $($_.Exception.Message)"
    }
}

function Install-GitHubCLI {
    Write-Info "Installing GitHub CLI..."
    
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVersion = & gh --version | Select-Object -First 1
        Write-Info "GitHub CLI already installed: $ghVersion"
        return
    }
    
    try {
        Write-Info "Installing GitHub CLI via winget..."
        $result = & winget install --id GitHub.cli --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Winget install failed with exit code: $LASTEXITCODE"
        }
        
        # Refresh PATH
        Update-Path
        
        # Verify installation
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            Write-Success "GitHub CLI installed successfully"
        } else {
            throw "GitHub CLI installation completed but gh command not found in PATH"
        }
    }
    catch {
        Write-ErrorCustom "Failed to install GitHub CLI: $($_.Exception.Message)"
        throw "Failed to install GitHub CLI: $($_.Exception.Message)"
    }
}

function Install-Docker {
    Write-Info "Installing Docker Desktop..."
    
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = & docker --version
        Write-Info "Docker already installed: $dockerVersion"
        return
    }
    
    try {
        # Enable Hyper-V and Containers features (required for Docker Desktop)
        $null = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
        $null = Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
        
        # Install Docker Desktop
        Write-Info "Installing Docker Desktop via winget..."
        $result = & winget install --id Docker.DockerDesktop --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Docker Desktop installation via winget failed. Manual installation may be required."
            Write-Info "Please download from: https://docs.docker.com/desktop/windows/install/"
        }
        
        Write-Success "Docker Desktop installed successfully"
        Write-Warning "A system restart may be required for Docker to function properly"
    }
    catch {
        Write-ErrorCustom "Failed to install Docker Desktop: $($_.Exception.Message)"
        Write-Info "Manual installation may be required from https://docs.docker.com/desktop/windows/install/"
    }
}

function Configure-Firewall {
    if ($SkipFirewall) {
        Write-Info "Skipping firewall configuration (--SkipFirewall specified)"
        return
    }
    
    # Get OS type
    $osInfo = Get-WindowsType
    
    # Check if user explicitly specified a mode via parameters
    $userSpecifiedMode = $false
    $forceServerMode = $false
    $forceLocalMode = $false
    
    if ($Mode -ieq "server" -or $Server) {
        $userSpecifiedMode = $true
        $forceServerMode = $true
    } elseif ($Mode -ieq "local" -or $Local -or $Development) {
        $userSpecifiedMode = $true
        $forceLocalMode = $true
    }
    
    # Determine action based on OS type and user parameters
    if ($osInfo.IsServer -and !$forceLocalMode) {
        # Server OS - configure firewall unless explicitly set to local mode
        Write-Info "Windows Server detected - configuring firewall for server deployment..."
        Configure-ServerFirewall
    }
    elseif (!$osInfo.IsServer -and !$forceServerMode) {
        # Desktop OS - skip firewall unless explicitly set to server mode
        Write-Info "Windows Desktop detected - skipping firewall configuration for local development"
        Write-Info "Firewall configuration is not needed for local development environments"
    }
    elseif ($forceServerMode) {
        # User explicitly wants server mode on desktop
        Write-Warning "Server mode forced on desktop OS - configuring firewall..."
        Configure-ServerFirewall
    }
    elseif ($forceLocalMode) {
        # User explicitly wants local mode on server
        Write-Warning "Local mode forced on server OS - skipping firewall configuration"
        Write-Info "Firewall configuration skipped by user request"
    }
}

function Configure-ServerFirewall {
    Write-Info "Configuring Windows Firewall for server deployment..."
    
    # Only configure ports actually used by Stack Masters
    # Removed ports 80 and 443 - not needed by Stack Masters
    [int[]]$ports = @(58217, 3000, 3001, 3002, 5678, 9090, 9999, 587, 465)  # 58217 is for provisioning wizard
    
    foreach ($port in $ports) {
        $currentPort = $port
        try {
            # Inbound rules
            New-NetFirewallRule -DisplayName "Stack Masters HTTP $currentPort (Inbound)" -Direction Inbound -Protocol TCP -LocalPort $currentPort -Action Allow -ErrorAction SilentlyContinue
            
            # Outbound rules
            New-NetFirewallRule -DisplayName "Stack Masters HTTP $currentPort (Outbound)" -Direction Outbound -Protocol TCP -LocalPort $currentPort -Action Allow -ErrorAction SilentlyContinue
            
            Write-Info "Firewall rule added for port $currentPort"
        }
        catch {
            Write-Warning "Failed to add firewall rule for port $($currentPort): $($_.Exception.Message)"
        }
    }
    
    Write-Success "Windows Firewall configured"
}

# GitHub authentication is now handled by the web wizard
# This function is kept for reference but no longer used
<#
function Authenticate-GitHub {
    # Moved to web wizard
}
#>

function Get-RepositoryUrl {
    if (-not [string]::IsNullOrEmpty($RepoUrl)) {
        return $RepoUrl
    }
    
    Write-Host ""
    Write-Info "Repository Setup"
    Write-Host "Please provide the GitHub repository URL to clone."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  - https://github.com/AI-Stack-Masters/stack-community" -ForegroundColor Cyan
    Write-Host "  - https://github.com/AI-Stack-Master-Pros/stack-pro" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "NOTE: Repository access requires Skool community membership:" -ForegroundColor Yellow
    Write-Host "  - AI Stack Masters (Free):  " -NoNewline
    Write-Host "https://www.skool.com/ai-stack-masters" -ForegroundColor Cyan
    Write-Host "  - AI Stack Master Pros (Paid): " -NoNewline
    Write-Host "https://www.skool.com/ai-stack-master-pros" -ForegroundColor Cyan
    Write-Host ""
    
    $url = Read-Host "Repository URL"
    
    if (-not ($url -match "^https://github\.com/[^/]+/[^/]+$")) {
        Write-ErrorCustom "Invalid GitHub repository URL format"
        Write-Info "Expected format: https://github.com/owner/repository"
        throw "Invalid GitHub repository URL format"
    }
    
    return $url
}

function Setup-ProvisioningWizard {
    Write-Info "Setting up Stack Masters Provisioning Wizard..."
    
    # Get the script's directory
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptDir)) {
        # Fallback for when running interactively
        $scriptDir = (Get-Location).Path
    }
    
    # Create run directory in the script directory
    $runDir = Join-Path $scriptDir "run"
    if (-not (Test-Path $runDir)) {
        New-Item -Path $runDir -ItemType Directory -Force | Out-Null
    }
    
    # Target directory for the wizard in the run folder
    $targetWizardDir = Join-Path $runDir "provisioning-wizard"
    
    # Source provisioning-web is included in this repository
    $sourceWizardDir = Join-Path $scriptDir "apps\provisioning-web"
    
    if (-not (Test-Path $sourceWizardDir)) {
        Write-ErrorCustom "Provisioning wizard source not found at: $sourceWizardDir"
        throw "Provisioning wizard source not found"
    }
    
    # Don't try to delete existing directory - just update it in place
    if (Test-Path $targetWizardDir) {
        Write-Info "Wizard directory already exists. Updating files in place..."
        
        # Clean up any PID files from previous runs
        $pidFiles = @(
            (Join-Path $targetWizardDir "wizard.pid"),
            (Join-Path $targetWizardDir "backend\wizard.pid")
        )
        foreach ($pidFile in $pidFiles) {
            if (Test-Path $pidFile) {
                Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        # Clean up any node_modules to ensure fresh install
        $nodeModulesDir = Join-Path $targetWizardDir "backend\node_modules"
        if (Test-Path $nodeModulesDir) {
            Write-Info "Cleaning up old node_modules..."
            # Use robocopy to delete node_modules (handles long paths better)
            $emptyDir = Join-Path $env:TEMP "empty_$(Get-Random)"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            & robocopy $emptyDir $nodeModulesDir /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP 2>&1 | Out-Null
            Remove-Item $emptyDir -Force
            Remove-Item $nodeModulesDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Clean up package-lock.json to avoid conflicts
        $packageLock = Join-Path $targetWizardDir "backend\package-lock.json"
        if (Test-Path $packageLock) {
            Remove-Item $packageLock -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        # Create new directory
        Write-Info "Creating wizard directory..."
        New-Item -Path $targetWizardDir -ItemType Directory -Force | Out-Null
    }
    
    Write-Info "Copying provisioning wizard files..."
    try {
        # Use robocopy for more reliable copying (handles locked files better)
        # /E = copy subdirectories including empty ones
        # /R:2 = retry 2 times
        # /W:1 = wait 1 second between retries
        # /XO = exclude older files (don't overwrite newer files)
        # /NFL /NDL = no file/directory listing
        # /NJH /NJS = no job header/summary
        $robocopyArgs = @(
            $sourceWizardDir,
            $targetWizardDir,
            "/E", "/R:2", "/W:1", "/XO",
            "/NFL", "/NDL", "/NJH", "/NJS"
        )
        
        $result = & robocopy @robocopyArgs
        $exitCode = $LASTEXITCODE
        
        # Robocopy exit codes: 0-7 are success codes, 8+ are errors
        if ($exitCode -ge 8) {
            throw "Robocopy failed with exit code $exitCode"
        }
        
        Write-Success "Provisioning wizard files updated successfully"
    }
    catch {
        Write-ErrorCustom "Failed to copy provisioning wizard: $($_.Exception.Message)"
        throw "Failed to copy provisioning wizard"
    }
    
    return $targetWizardDir
}

function Start-ProvisioningWizard {
    param(
        [string]$WizardDir
    )
    
    Write-Info "Starting Stack Masters Provisioning Wizard..."
    
    # The wizard directory is already the provisioning-web directory
    if (-not (Test-Path $WizardDir)) {
        Write-ErrorCustom "Provisioning wizard directory not found: $WizardDir"
        throw "Provisioning wizard directory not found"
    }
    
    # Check if Node.js is available
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Info "Node.js not found. Installing Node.js..."
        try {
            & winget install --id OpenJS.NodeJS --exact --silent --accept-package-agreements --accept-source-agreements
            Update-Path
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                throw "Node.js installation completed but node command not found"
            }
        }
        catch {
            Write-ErrorCustom "Failed to install Node.js: $($_.Exception.Message)"
            throw
        }
    }
    
    # Validate Node.js installation
    Write-Info "Validating Node.js installation..."
    try {
        $nodeVersion = & node --version 2>&1
        Write-Info "Node.js version: $nodeVersion"
    }
    catch {
        Write-ErrorCustom "Node.js validation failed: $($_.Exception.Message)"
        throw
    }
    
    # Check if npm is available
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-ErrorCustom "npm is not available. Please ensure Node.js installation includes npm."
        throw "npm not found"
    }
    
    # Validate npm
    try {
        $npmVersion = & npm --version 2>&1
        Write-Info "npm version: $npmVersion"
    }
    catch {
        Write-ErrorCustom "npm validation failed: $($_.Exception.Message)"
        throw
    }
    
    # Navigate to backend directory
    $backendDir = Join-Path $WizardDir "backend"
    if (-not (Test-Path $backendDir)) {
        Write-ErrorCustom "Backend directory not found: $backendDir"
        throw "Backend directory not found"
    }
    
    # Save current location
    $originalLocation = Get-Location
    
    try {
        Set-Location $backendDir
        
        Write-Info "Installing dependencies..."
        Write-Info "Working directory: $backendDir"
        
        # Simple direct approach - just run npm install
        Write-Info "Running npm install (this may take a minute)..."
        
        $npmInstallResult = $null
        $npmInstallError = $null
        
        # Try different methods to run npm install
        try {
            # Method 1: Direct invocation
            $npmInstallResult = npm install --production 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "npm install completed successfully"
            }
            else {
                throw "npm install failed with exit code: $LASTEXITCODE"
            }
        }
        catch {
            Write-Warning "Direct npm invocation failed, trying alternative method..."
            
            # Method 2: Use Invoke-Expression
            try {
                $npmInstallResult = Invoke-Expression "npm install --production 2>&1"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "npm install completed successfully"
                }
                else {
                    throw "npm install failed"
                }
            }
            catch {
                # Method 3: Last resort - tell user to do it manually
                Write-ErrorCustom "Automated npm install failed"
                Write-Info "Please run the following commands manually:"
                Write-Host "  cd `"$backendDir`"" -ForegroundColor Yellow
                Write-Host "  npm install --production" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Then press any key to continue..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                # Verify node_modules exists
                if (-not (Test-Path (Join-Path $backendDir "node_modules"))) {
                    throw "node_modules directory not found. Please ensure npm install completed successfully."
                }
                Write-Success "Continuing with manual npm install"
            }
        }
        
        Write-Success "Dependencies installed successfully"
    }
    catch {
        Set-Location $originalLocation
        throw
    }
    
    # Set environment variables
    # PROJECT_ROOT will be set after cloning via web wizard
    # Use a unique port that's unlikely to conflict with other services
    $env:PORT = "58217"  # Random high port to avoid conflicts
    $env:NODE_ENV = "production"
    
    # Detect environment and set HOST
    $osInfo = Get-WindowsType
    $env:HOST = if ($osInfo.Type -eq "Desktop") { "localhost" } else { "0.0.0.0" }
    
    Write-Info "Starting provisioning wizard on port 58217..."
    
    # Start the backend server in detached mode
    Write-Info "Starting Node.js server in background..."
    
    # Create a batch file to start the Node.js server
    # This ensures proper execution regardless of Node.js installation method
    $startBatchFile = Join-Path $WizardDir "start-wizard.bat"
    $startBatchContent = @"
@echo off
cd /d "$backendDir"
set PORT=$($env:PORT)
set NODE_ENV=$($env:NODE_ENV)
set HOST=$($env:HOST)
start /b node server-integrated.js > wizard.log 2>&1
echo %ERRORLEVEL% > wizard.pid
"@
    
    Set-Content -Path $startBatchFile -Value $startBatchContent -Encoding ASCII
    
    Write-Info "Starting Node.js server..."
    
    # Start the server using the batch file
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$startBatchFile`"" -WindowStyle Hidden -PassThru
    
    if ($null -eq $process) {
        Write-ErrorCustom "Failed to start Node.js server"
        Set-Location $originalLocation
        throw "Failed to start Node.js process"
    }
    
    # The batch file starts node in background, so we need to find the actual node process
    Start-Sleep -Seconds 3
    
    # Find the node process on our port
    $nodeProcess = $null
    $retries = 0
    while ($null -eq $nodeProcess -and $retries -lt 5) {
        try {
            $tcpConnection = Get-NetTCPConnection -LocalPort $env:PORT -State Listen -ErrorAction SilentlyContinue
            if ($tcpConnection) {
                $nodeProcess = Get-Process -Id $tcpConnection.OwningProcess -ErrorAction SilentlyContinue
                if ($nodeProcess) {
                    Write-Info "Node.js server started with PID: $($nodeProcess.Id)"
                    # Save the actual node process PID
                    $pidFile = Join-Path $WizardDir "wizard.pid"
                    Set-Content -Path $pidFile -Value $nodeProcess.Id
                    break
                }
            }
        }
        catch {
            # Ignore errors
        }
        $retries++
        Start-Sleep -Seconds 2
    }
    
    if ($null -eq $nodeProcess) {
        Write-Warning "Could not verify Node.js process, but it may still be starting..."
    }
    
    Write-Info "Provisioning wizard started with PID: $($process.Id)"
    Write-Info "Waiting for server to be ready..."
    Start-Sleep -Seconds 8
    
    # Save PID for potential cleanup
    $pidFile = Join-Path $WizardDir "wizard.pid"
    Set-Content -Path $pidFile -Value $process.Id
    
    # Test if server is accessible
    try {
        $testResponse = Invoke-WebRequest -Uri "http://localhost:58217/api/health" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($testResponse.StatusCode -eq 200) {
            Write-Success "Server is responding on port 58217 ✓"
        } else {
            Write-Warning "Server may not be fully ready yet. Check http://localhost:58217 in a moment."
        }
    } catch {
        Write-Warning "Unable to verify server status. Please check http://localhost:58217 manually."
    }
    
    # Display access information
    Write-Success "Provisioning wizard is running!"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Stack Masters Provisioning Wizard" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access the wizard at:" -ForegroundColor Yellow
    Write-Host "  http://localhost:58217" -ForegroundColor Cyan
    Write-Host ""
    
    # Get server IPs for remote access
    $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown"
    } | Select-Object -ExpandProperty IPAddress
    
    if ($ipAddresses) {
        Write-Host "From a remote machine:" -ForegroundColor Yellow
        foreach ($ip in $ipAddresses) {
            Write-Host "  http://${ip}:58217" -ForegroundColor Cyan
        }
    }
    Write-Host ""
    Write-Host "The wizard will guide you through:" -ForegroundColor Yellow
    Write-Host "  - Selecting your Stack Masters repository" -ForegroundColor White
    Write-Host "  - Configuring your environment" -ForegroundColor White
    Write-Host "  - Deploying your services" -ForegroundColor White
    Write-Host ""
    
    # Return to original location
    Set-Location $originalLocation
}

# Repository cloning is now handled by the web wizard
# This function is kept for reference but no longer used
<#
function Clone-Repository {
    # Moved to web wizard - handled via /api/github/clone endpoint
}
#>

function Stop-ExistingWizard {
    Write-Info "Checking for existing wizard processes..."
    
    # Check if port 58217 is in use
    $tcpConnection = Get-NetTCPConnection -LocalPort 58217 -ErrorAction SilentlyContinue
    if ($tcpConnection) {
        Write-Warning "Port 58217 is in use. Attempting to stop existing wizard..."
        
        # Try to identify the process using the port
        foreach ($conn in $tcpConnection) {
            try {
                $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Info "Found process using port 58217: $($process.Name) (PID: $($process.Id))"
                    
                    # If it's a node process, likely our wizard
                    if ($process.Name -eq "node" -or $process.Name -eq "node.exe") {
                        Write-Info "Stopping Node.js wizard process..."
                        Stop-Process -Id $process.Id -Force
                        Write-Success "Wizard process stopped"
                        
                        # Wait a moment for port to be released
                        Start-Sleep -Seconds 2
                    }
                    else {
                        Write-Warning "Port 58217 is used by: $($process.Name)"
                        Write-Warning "Please close this application manually or choose a different port"
                    }
                }
            }
            catch {
                Write-Warning "Could not identify process using port 58217"
            }
        }
    }
    
    # Also check for any node processes in our wizard directory
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptDir)) {
        $scriptDir = (Get-Location).Path
    }
    
    $wizardDirs = @(
        (Join-Path $scriptDir "run\provisioning-wizard"),
        (Join-Path $scriptDir "apps\provisioning-web")
    )
    
    $nodeProcesses = @(Get-Process -Name "node" -ErrorAction SilentlyContinue)
    if ($nodeProcesses.Count -gt 0) {
        foreach ($proc in $nodeProcesses) {
            try {
                # Get the command line to check if it's our wizard
                $commandLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                
                foreach ($wizardDir in $wizardDirs) {
                    if ($commandLine -and $commandLine.Contains($wizardDir)) {
                        Write-Info "Found wizard process: PID $($proc.Id)"
                        Stop-Process -Id $proc.Id -Force
                        Write-Success "Stopped wizard process"
                    }
                }
            }
            catch {
                # Ignore errors in process inspection
            }
        }
    }
    
    # Clean up any PID files
    foreach ($wizardDir in $wizardDirs) {
        $pidFiles = @(
            (Join-Path $wizardDir "wizard.pid"),
            (Join-Path $wizardDir "backend\wizard.pid")
        )
        
        foreach ($pidFile in $pidFiles) {
            if (Test-Path $pidFile) {
                try {
                    $pid = Get-Content $pidFile -Raw
                    if ($pid -match '^\d+$') {
                        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                        if ($process) {
                            Write-Info "Stopping process from PID file: $pid"
                            Stop-Process -Id $pid -Force
                        }
                    }
                    Remove-Item $pidFile -Force
                }
                catch {
                    # Ignore errors
                }
            }
        }
    }
}

function Test-SystemRequirements {
    Write-Info "Running comprehensive system validation..."
    
    $validationErrors = 0
    
    # Check disk space (minimum 10GB - sufficient for Docker images and data)
    Write-Info "Checking disk space..."
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $totalSpaceGB = [math]::Round($disk.Size / 1GB, 1)
    
    if ($freeSpaceGB -lt 10) {
        Write-ErrorCustom "Insufficient disk space: ${freeSpaceGB}GB available, 10GB required"
        $validationErrors++
    }
    elseif ($freeSpaceGB -lt 15) {
        Write-Warning "Low disk space: ${freeSpaceGB}GB available. Consider having at least 15GB for optimal performance."
        Write-Success "Disk space: ${freeSpaceGB}GB available (minimum requirement met) ✓"
    }
    else {
        Write-Success "Disk space: ${freeSpaceGB}GB available of ${totalSpaceGB}GB total ✓"
    }
    
    # Check memory (minimum 4GB)
    Write-Info "Checking system memory..."
    $totalMemory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    # FreePhysicalMemory is in KB, so convert to GB
    $availableMemory = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1024 / 1024
    
    if ($totalMemory -lt 4) {
        Write-ErrorCustom "Insufficient memory: $($totalMemory.ToString('N1'))GB total, 4GB required"
        $validationErrors++
    }
    else {
        Write-Success "Memory: $($totalMemory.ToString('N1'))GB total, $($availableMemory.ToString('N1'))GB available ✓"
    }
    
    # Check CPU cores
    Write-Info "Checking CPU cores..."
    $cpuCores = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
    if ($cpuCores -lt 2) {
        Write-Warning "Only $cpuCores CPU core(s) detected. Performance may be limited."
    }
    else {
        Write-Success "CPU cores: $cpuCores ✓"
    }
    
    # Validate Docker
    Write-Info "Validating Docker installation..."
    $dockerInstalled = $false
    
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerInstalled = $true
        
        # Check if Docker daemon is running
        try {
            $dockerInfo = & docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Docker daemon is running ✓"
                
                # Test Docker functionality
                $testResult = & docker run --rm hello-world 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Docker functionality verified ✓"
                }
                else {
                    Write-ErrorCustom "Docker test failed. Please check Docker Desktop."
                    $validationErrors++
                }
            }
            else {
                Write-Warning "Docker daemon is not running. Please start Docker Desktop."
                $validationErrors++
            }
        }
        catch {
            Write-ErrorCustom "Docker daemon check failed: $($_.Exception.Message)"
            $validationErrors++
        }
    }
    else {
        Write-ErrorCustom "Docker is not installed"
        $validationErrors++
    }
    
    # Check Docker Compose
    Write-Info "Checking Docker Compose..."
    if ($dockerInstalled) {
        try {
            $composeVersion = & docker compose version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Docker Compose available ✓"
            }
            else {
                # Try older docker-compose command
                $oldComposeVersion = & docker-compose --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Docker Compose (standalone) available ✓"
                }
                else {
                    Write-ErrorCustom "Docker Compose not found"
                    $validationErrors++
                }
            }
        }
        catch {
            Write-ErrorCustom "Docker Compose check failed"
            $validationErrors++
        }
    }
    
    # Check port availability
    Write-Info "Checking port availability..."
    function Test-PortAvailability {
        param($Port, $ServiceName)
        
        $tcpConnection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($tcpConnection) {
            Write-ErrorCustom "Port $Port is already in use (required for $ServiceName)"
            return $false
        }
        return $true
    }
    
    # Check wizard port
    if (Test-PortAvailability -Port 58217 -ServiceName "Provisioning Wizard") {
        Write-Success "Port 58217 available for wizard ✓"
    }
    else {
        $validationErrors++
    }
    
    # Check other ports used by Stack Masters services (warnings only)
    # Removed ports 80 and 443 - not needed by Stack Masters
    $warningPorts = @(3000, 3001, 5678, 9090)
    foreach ($port in $warningPorts) {
        if (-not (Test-PortAvailability -Port $port -ServiceName "Stack Services")) {
            Write-Warning "Port $port is in use. This may cause conflicts during deployment."
        }
    }
    
    # Test internet connectivity
    Write-Info "Checking internet connectivity..."
    try {
        $response = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Success "Internet connectivity verified ✓"
        }
    }
    catch {
        Write-ErrorCustom "No internet connectivity detected. Please check your network connection."
        $validationErrors++
    }
    
    # Check if running as Administrator
    if (-not (Test-Administrator)) {
        Write-ErrorCustom "This script must be run as Administrator"
        $validationErrors++
    }
    else {
        Write-Success "Running with Administrator privileges ✓"
    }
    
    # Check Windows version
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $osVersion = [Version]$osInfo.Version
    if ($osVersion.Major -lt 10) {
        Write-Warning "Windows version may not be fully supported: $($osInfo.Caption)"
    }
    else {
        Write-Success "Windows version supported: $($osInfo.Caption) ✓"
    }
    
    # Summary
    Write-Host ""
    if ($validationErrors -eq 0) {
        Write-Success "All system validation checks passed! ✓"
        return $true
    }
    else {
        Write-ErrorCustom "System validation failed with $validationErrors error(s)"
        Write-Info "Please resolve the issues above and try again"
        return $false
    }
}

function Test-WizardDiagnostics {
    Write-Info "Running wizard pre-flight diagnostics..."
    $diagnosticErrors = 0
    
    # Check Node.js installation
    Write-Info "Checking Node.js installation..."
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-ErrorCustom "Node.js is not installed or not in PATH"
        Write-Info "Please install Node.js from https://nodejs.org/"
        $diagnosticErrors++
    }
    else {
        $nodeVersion = & node --version 2>&1
        Write-Success "Node.js installed: $nodeVersion"
    }
    
    # Check npm installation
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-ErrorCustom "npm is not installed or not in PATH"
        $diagnosticErrors++
    }
    else {
        $npmVersion = & npm --version 2>&1
        Write-Success "npm installed: $npmVersion"
    }
    
    # Check if port 58217 is available (more thorough check)
    Write-Info "Checking port 58217 availability..."
    $tcpConnections = Get-NetTCPConnection -LocalPort 58217 -ErrorAction SilentlyContinue
    if ($tcpConnections) {
        Write-ErrorCustom "Port 58217 is already in use!"
        
        # Try to identify the process
        foreach ($conn in $tcpConnections) {
            try {
                $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                Write-ErrorCustom "  Process using port: $($process.Name) (PID: $($process.Id))"
            }
            catch {
                Write-ErrorCustom "  Process using port: PID $($conn.OwningProcess)"
            }
        }
        
        Write-Info "Please stop the process using port 58217 or choose a different port"
        $diagnosticErrors++
    }
    else {
        Write-Success "Port 58217 is available"
    }
    
    # Return object with diagnostic results
    return @{
        HasCriticalIssues = ($diagnosticErrors -gt 0)
        ErrorCount = $diagnosticErrors
    }
}

function Start-ProvisioningWizard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WizardDir
    )
    
    Write-Info "Starting Stack Masters Provisioning Wizard..."
    
    $backendDir = Join-Path $WizardDir "backend"
    if (-not (Test-Path $backendDir)) {
        Write-ErrorCustom "Backend directory not found: $backendDir"
        throw "Backend directory not found"
    }
    
    Push-Location $backendDir
    try {
        # Validate Node.js installation
        Write-Info "Validating Node.js installation..."
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Write-ErrorCustom "Node.js is not installed or not in PATH"
            throw "Node.js not found"
        }
        
        $nodeVersion = & node --version 2>&1
        Write-Info "Node.js version: $nodeVersion"
        
        # Validate package.json exists
        $packageJsonPath = Join-Path $backendDir "package.json"
        if (-not (Test-Path $packageJsonPath)) {
            Write-ErrorCustom "package.json not found in backend directory"
            throw "package.json not found"
        }
        
        # Install dependencies with error checking
        Write-Info "Installing dependencies..."
        
        # Method 1: Try using cmd.exe to run npm to handle .cmd files properly on Windows
        try {
            $npmArgs = "/c npm install --production"
            $npmProcess = Start-Process -FilePath "cmd.exe" -ArgumentList $npmArgs -WorkingDirectory $backendDir -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$logsDir\npm-install-output.log" -RedirectStandardError "$logsDir\npm-install-error.log"
            
            if ($npmProcess.ExitCode -eq 0) {
                Write-Success "Dependencies installed successfully"
            }
            else {
                throw "npm install failed with exit code $($npmProcess.ExitCode)"
            }
        }
        catch {
            Write-Warning "cmd.exe npm install failed: $_"
            
            # Method 2: Try direct npm.cmd execution
            Write-Info "Trying alternative npm installation method..."
            try {
                $npmCmd = Get-Command npm -ErrorAction Stop
                $npmPath = $npmCmd.Source
                Write-Info "Found npm at: $npmPath"
                
                # Execute npm directly
                $result = & $npmPath install --production 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Dependencies installed successfully (alternative method)"
                }
                else {
                    throw "npm install failed with exit code $LASTEXITCODE"
                }
            }
            catch {
                Write-ErrorCustom "All npm installation methods failed"
                Write-ErrorCustom "Error details: $_"
                
                # Check if node_modules exists (maybe from previous run)
                $nodeModulesPath = Join-Path $backendDir "node_modules"
                if (Test-Path $nodeModulesPath) {
                    Write-Warning "node_modules directory exists - attempting to continue"
                }
                else {
                    Write-ErrorCustom "Please run 'npm install --production' manually in: $backendDir"
                    throw "npm installation failed"
                }
            }
        }
        
        # Check if port 58217 is available
        Write-Info "Checking port availability..."
        $portInUse = Get-NetTCPConnection -LocalPort 58217 -ErrorAction SilentlyContinue
        if ($portInUse) {
            Write-ErrorCustom "Port 58217 is already in use by another process"
            Write-Info "To find what's using the port: netstat -ano | findstr :58217"
            throw "Port 58217 is not available"
        }
        
        # Determine host binding
        $osInfo = Get-WindowsType
        $hostBinding = if ($osInfo.IsServer -or $Server -or ($Mode -eq "server")) { "0.0.0.0" } else { "localhost" }
        
        Write-Info "Starting Node.js server..."
        Write-Info "Host binding: $hostBinding"
        Write-Info "Working directory: $backendDir"
        
        # Try multiple methods to start Node.js process
        $nodeProcess = $null
        $startError = $null
        
        # Method 1: Try using Start-Process with proper arguments
        try {
            Write-Info "Attempting to start wizard with Start-Process..."
            
            # Create environment block
            $env:HOST = $hostBinding
            $env:PORT = "58217"
            $env:NODE_ENV = "production"
            
            # Start the process using Start-Process cmdlet
            $nodeProcess = Start-Process -FilePath "node" `
                -ArgumentList "server-integrated.js" `
                -WorkingDirectory $backendDir `
                -PassThru `
                -NoNewWindow `
                -RedirectStandardOutput "$logsDir\wizard-output.log" `
                -RedirectStandardError "$logsDir\wizard-error.log"
            
            if ($nodeProcess -and !$nodeProcess.HasExited) {
                Write-Success "Wizard process started successfully (Method 1)"
            }
            else {
                throw "Process failed to start or exited immediately"
            }
        }
        catch {
            $startError = $_
            Write-Warning "Start-Process method failed: $_"
            
            # Method 2: Try using .NET ProcessStartInfo
            try {
                Write-Info "Attempting alternative start method..."
                
                # Get the full path to node.exe to avoid Win32 errors
                $nodePath = (Get-Command node -ErrorAction Stop).Source
                Write-Info "Node.js path: $nodePath"
                
                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $nodePath
                $processInfo.Arguments = "server-integrated.js"
                $processInfo.WorkingDirectory = $backendDir
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $false
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                
                # Set environment variables
                $processInfo.EnvironmentVariables["HOST"] = $hostBinding
                $processInfo.EnvironmentVariables["PORT"] = "58217"
                $processInfo.EnvironmentVariables["NODE_ENV"] = "production"
                
                # Start the process
                $nodeProcess = [System.Diagnostics.Process]::Start($processInfo)
                
                if ($nodeProcess) {
                    Write-Success "Wizard process started successfully (Method 2)"
                }
            }
            catch {
                Write-Warning "ProcessStartInfo method failed: $_"
                
                # Method 3: Last resort - use cmd.exe to start node
                try {
                    Write-Info "Attempting cmd.exe start method..."
                    
                    # Create a batch command to start node
                    $cmdArgs = "/c `"cd /d `"$backendDir`" && set HOST=$hostBinding && set PORT=58217 && set NODE_ENV=production && start /b node server-integrated.js > `"$logsDir\wizard-output.log`" 2> `"$logsDir\wizard-error.log`"`""
                    
                    $nodeProcess = Start-Process -FilePath "cmd.exe" `
                        -ArgumentList $cmdArgs `
                        -PassThru `
                        -WindowStyle Hidden
                    
                    # Give it a moment to start
                    Start-Sleep -Seconds 2
                    
                    # Try to find the node process
                    $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Path -and (Split-Path $_.Path -Leaf) -eq "node.exe" }
                    
                    if ($nodeProcesses) {
                        $nodeProcess = $nodeProcesses | Select-Object -First 1
                        Write-Success "Wizard process started successfully (Method 3)"
                    }
                    else {
                        throw "Node process not found after cmd.exe start"
                    }
                }
                catch {
                    Write-ErrorCustom "All start methods failed"
                    Write-ErrorCustom "Last error: $_"
                    Write-ErrorCustom "Original error: $startError"
                    
                    # Show manual instructions
                    Write-Host ""
                    Write-Warning "MANUAL START REQUIRED:"
                    Write-Info "Please try starting the wizard manually:"
                    Write-Info "  1. Open a new Command Prompt or PowerShell as Administrator"
                    Write-Info "  2. Run these commands:"
                    Write-Host "     cd `"$backendDir`"" -ForegroundColor Cyan
                    Write-Host "     set HOST=$hostBinding" -ForegroundColor Cyan
                    Write-Host "     set PORT=58217" -ForegroundColor Cyan
                    Write-Host "     set NODE_ENV=production" -ForegroundColor Cyan
                    Write-Host "     node server-integrated.js" -ForegroundColor Cyan
                    Write-Host ""
                    
                    throw "Failed to start Node.js process automatically"
                }
            }
        }
        
        if (-not $nodeProcess) {
            Write-ErrorCustom "Failed to start Node.js process"
            throw "Failed to start Node.js process"
        }
        
        Write-Info "Node.js process started with PID: $($nodeProcess.Id)"
        
        # Save PID for cleanup
        $pidFile = Join-Path $wizardDir "wizard.pid"
        Set-Content -Path $pidFile -Value $nodeProcess.Id
        
        # Monitor startup for errors (first 10 seconds)
        Write-Info "Monitoring startup for errors..."
        $startupTimeout = 10
        $startupTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $processStarted = $false
        $hasErrors = $false
        
        while ($startupTimer.Elapsed.TotalSeconds -lt $startupTimeout) {
            # Check if process is still running
            if ($nodeProcess.HasExited) {
                $exitCode = $nodeProcess.ExitCode
                Write-ErrorCustom "Node.js process exited unexpectedly with code: $exitCode"
                
                # Try to read stderr for error details
                try {
                    $errorOutput = $nodeProcess.StandardError.ReadToEnd()
                    if ($errorOutput) {
                        Write-ErrorCustom "Process error output: $errorOutput"
                    }
                } catch {
                    Write-Warning "Could not read process error output"
                }
                
                $hasErrors = $true
                break
            }
            
            # Check if server is responding - try multiple endpoints
            try {
                # Try health endpoint first
                $healthResponse = Invoke-WebRequest -Uri "http://$hostBinding:58217/api/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($healthResponse.StatusCode -eq 200) {
                    $processStarted = $true
                    break
                }
            }
            catch {
                # Health endpoint might require auth, try the root endpoint
                try {
                    $rootResponse = Invoke-WebRequest -Uri "http://$hostBinding:58217/" -TimeoutSec 2 -ErrorAction SilentlyContinue
                    if ($rootResponse.StatusCode -eq 200 -or $rootResponse.StatusCode -eq 401 -or $rootResponse.StatusCode -eq 403) {
                        # Server is responding (even if it returns auth errors, that means it's running)
                        $processStarted = $true
                        break
                    }
                }
                catch {
                    # Still starting up, continue waiting
                }
            }
            
            Start-Sleep -Milliseconds 500
        }
        
        $startupTimer.Stop()
        
        # Determine startup result
        if ($hasErrors) {
            throw "Node.js process failed to start properly"
        }
        elseif ($processStarted) {
            Write-Success "Provisioning wizard started successfully!"
            Write-Success "Health check passed: server is responding on port 58217"
            Show-WizardAccessInfo -HostBinding $hostBinding
        }
        else {
            # Process is running but not responding
            Write-ErrorCustom "Node.js process is running but server is not responding on port 58217"
            Write-ErrorCustom "This usually indicates a configuration or dependency issue"
            
            # Try to get some output from the process
            try {
                if (-not $nodeProcess.StandardOutput.EndOfStream) {
                    $output = $nodeProcess.StandardOutput.ReadToEnd()
                    if ($output) {
                        Write-Info "Process output: $output"
                    }
                }
                if (-not $nodeProcess.StandardError.EndOfStream) {
                    $errorOutput = $nodeProcess.StandardError.ReadToEnd()
                    if ($errorOutput) {
                        Write-ErrorCustom "Process errors: $errorOutput"
                    }
                }
            } catch {
                Write-Warning "Could not read process output"
            }
            
            # Kill the non-responsive process
            try {
                $nodeProcess.Kill()
                Write-Info "Terminated non-responsive process"
            } catch {
                Write-Warning "Could not terminate process - it may still be running"
            }
            
            throw "Server failed to start - check logs for details"
        }
        
        # Save wizard info to file for later reference
        $wizardInfoFile = Join-Path $wizardDir "wizard-info.txt"
        
        # Build URLs for the info file
        $localUrl = "http://localhost:58217"
        $remoteUrls = @()
        
        if ($hostBinding -ne "localhost") {
            try {
                $networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
                    $_.IPAddress -ne "127.0.0.1" -and 
                    ($_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual") 
                }
                foreach ($adapter in $networkAdapters) {
                    $remoteUrls += "  http://$($adapter.IPAddress):58217"
                }
            }
            catch {
                $remoteUrls += "  http://YOUR-SERVER-IP:58217"
            }
        }
        
        $wizardInfo = @"
Stack Masters Provisioning Wizard Information
=============================================
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Status: RUNNING
Process ID: $($nodeProcess.Id)

Access URLs:
  Local:  $localUrl
$(if ($remoteUrls.Count -gt 0) { "  Remote:`n" + ($remoteUrls -join "`n") })

System Information:
  Backend Directory: $backendDir
  Host Binding: $hostBinding
  Log Files Directory: $logsDir
  Node.js Version: $nodeVersion

Management Commands:
  Check if running:   Get-Process -Id $($nodeProcess.Id) -ErrorAction SilentlyContinue
  Stop wizard:        Stop-Process -Id $($nodeProcess.Id) -Force
  Check port status:  netstat -ano | findstr :58217
  View logs:          Get-Content "$logsDir\stack-masters-setup-*.log" -Tail 50

Troubleshooting:
  If wizard stops responding:
    1. Check process: Get-Process -Id $($nodeProcess.Id)
    2. Check port: netstat -ano | findstr :58217  
    3. View recent logs in: $logsDir
    4. Restart manually: cd "$backendDir" && node server-integrated.js
"@
        Set-Content -Path $wizardInfoFile -Value $wizardInfo
        Write-Info "Wizard information saved to: $wizardInfoFile"
        
    }
    finally {
        Pop-Location
    }
}

function Test-WizardDiagnostics {
    Write-Info "Running wizard diagnostics..."
    
    $issues = @()
    $warnings = @()
    
    # Check Node.js
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        $issues += "Node.js is not installed or not in PATH"
    } else {
        $nodeVersion = & node --version 2>&1
        if ($nodeVersion -match "v(\d+)\.") {
            $majorVersion = [int]$matches[1]
            if ($majorVersion -lt 16) {
                $warnings += "Node.js version $nodeVersion is below recommended v16+"
            }
        }
    }
    
    # Check npm
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        $issues += "npm is not installed or not in PATH"
    }
    
    # Check port 58217
    $portInUse = Get-NetTCPConnection -LocalPort 58217 -ErrorAction SilentlyContinue
    if ($portInUse) {
        $processId = $portInUse.OwningProcess
        $processName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
        $issues += "Port 58217 is already in use by process: $processName (PID: $processId)"
    }
    
    # Check Windows Firewall (for server environments)
    $osInfo = Get-WindowsType
    if ($osInfo.IsServer) {
        try {
            $firewallRule = Get-NetFirewallRule -DisplayName "*Stack Masters*58217*" -ErrorAction SilentlyContinue
            if (-not $firewallRule) {
                $warnings += "No firewall rule found for port 58217 on server OS"
            }
        }
        catch {
            $warnings += "Could not check firewall rules"
        }
    }
    
    # Check available memory
    $availableMemoryGB = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1024 / 1024
    if ($availableMemoryGB -lt 1) {
        $warnings += "Low available memory: $($availableMemoryGB.ToString('N1'))GB (recommend 1GB+)"
    }
    
    # Check disk space in temp directory
    $tempDrive = (Get-Item $env:TEMP).PSDrive.Name
    $diskSpace = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${tempDrive}:'"
    $freeSpaceGB = [math]::Round($diskSpace.FreeSpace / 1GB, 1)
    if ($freeSpaceGB -lt 2) {
        $issues += "Low disk space on ${tempDrive}: drive: ${freeSpaceGB}GB (need 2GB+)"
    }
    
    # Report results
    if ($issues.Count -gt 0) {
        Write-ErrorCustom "Critical issues found:"
        foreach ($issue in $issues) {
            Write-Host "  • $issue" -ForegroundColor Red
        }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Warning "Potential issues found:"
        foreach ($warning in $warnings) {
            Write-Host "  • $warning" -ForegroundColor Yellow
        }
    }
    
    if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
        Write-Success "No issues detected"
    }
    
    return @{
        HasCriticalIssues = $issues.Count -gt 0
        CriticalIssues = $issues
        Warnings = $warnings
    }
}

function Show-WizardAccessInfo {
    param([string]$HostBinding)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   Stack Masters Provisioning Wizard" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "✅ Wizard is running successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access the wizard at:" -ForegroundColor Cyan
    
    if ($HostBinding -eq "localhost") {
        Write-Host "  🌐 http://localhost:58217" -ForegroundColor Yellow
    }
    else {
        Write-Host "  🌐 http://localhost:58217" -ForegroundColor Yellow
        
        # Show network interfaces for remote access
        try {
            $networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
                $_.IPAddress -ne "127.0.0.1" -and 
                ($_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual") 
            }
            if ($networkAdapters) {
                Write-Host ""
                Write-Host "Remote access URLs:" -ForegroundColor Cyan
                foreach ($adapter in $networkAdapters) {
                    Write-Host "  🌐 http://$($adapter.IPAddress):58217" -ForegroundColor Yellow
                }
            }
        }
        catch {
            # Fallback if network detection fails
            Write-Host ""
            Write-Host "Remote access:" -ForegroundColor Cyan
            Write-Host "  🌐 http://YOUR-SERVER-IP:58217" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "The wizard will guide you through:" -ForegroundColor Cyan
    Write-Host "  📋 System validation and requirements check" -ForegroundColor White
    Write-Host "  🔐 GitHub authentication and repository selection" -ForegroundColor White
    Write-Host "  ⚙️  Environment configuration" -ForegroundColor White
    Write-Host "  🚀 Service deployment and health monitoring" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 Keep this terminal window open while using the wizard" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ℹ️  To restart the wizard, simply run this script again:" -ForegroundColor Cyan
    Write-Host "  .\setup-windows.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "✨ The wizard will auto-shutdown 10 minutes after deployment completes" -ForegroundColor Green
    Write-Host ""
}

function Main {
    Clear-Host
    
    # Detect OS type
    $osInfo = Get-WindowsType
    
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   Stack Masters Windows Setup Script v$VERSION" -ForegroundColor Cyan
    Write-Host "   $($osInfo.Name)" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Help) {
        Show-Help
        exit 0
    }
    
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        Write-ErrorCustom "This script must be run as Administrator"
        Write-Info "Please run PowerShell as Administrator and try again"
        throw "This script must be run as Administrator"
    }
    
    Write-Info "Starting Stack Masters setup..."
    Write-Info "Detected OS: $($osInfo.Name)"
    Write-Info "OS Type: $($osInfo.Type)"
    Write-Info "Log file: $script:LogFile"
    Write-Host ""
    
    # Display what this script will do
    Write-Host "This script will:" -ForegroundColor Yellow
    Write-Host "  1. Check your system for required packages" -ForegroundColor Yellow
    Write-Host "  2. Install missing packages (with your permission)" -ForegroundColor Yellow
    if ($osInfo.IsServer) {
        Write-Host "  3. Configure Windows Firewall (Server OS detected)" -ForegroundColor Yellow
    } else {
        Write-Host "  3. Skip firewall configuration (Desktop OS detected)" -ForegroundColor Yellow
    }
    Write-Host "  4. Authenticate with GitHub" -ForegroundColor Yellow
    Write-Host "  5. Setup Stack Masters Provisioning Wizard" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
    
    # Check system packages
    $packageStatus = Check-SystemPackages
    
    # Confirm installation with user
    $proceedWithInstall = Confirm-Installation -PackageStatus $packageStatus
    if (-not $proceedWithInstall) {
        Write-Info "Setup cancelled"
        exit 0
    }
    
    # Install missing components
    if (-not $packageStatus.Git) {
        Install-Git
    }
    
    if (-not $packageStatus.GitHubCLI) {
        Install-GitHubCLI
    }
    
    if (-not $packageStatus.Docker) {
        Install-Docker
    }
    
    # Configure system
    Configure-Firewall
    
    # Stop any existing wizard processes to free up port 58217
    Stop-ExistingWizard
    
    # Run comprehensive system validation
    Write-Info "Performing system validation..."
    if (-not (Test-SystemRequirements)) {
        Write-ErrorCustom "System validation failed. Please fix the issues and try again."
        exit 1
    }
    
    # Run wizard-specific diagnostics
    Write-Host ""
    $diagnostics = Test-WizardDiagnostics
    if ($diagnostics.HasCriticalIssues) {
        Write-ErrorCustom "Critical issues detected that will prevent the wizard from starting"
        Write-Info "Please resolve the issues above and try again"
        exit 1
    }
    
    # Stop any existing wizard processes
    Write-Host ""
    Stop-ExistingWizard
    
    # Setup and start provisioning wizard
    Write-Host ""
    Write-Info "All checks passed - setting up provisioning wizard..."
    $wizardDir = Setup-ProvisioningWizard
    
    try {
        Start-ProvisioningWizard -WizardDir $wizardDir
        
        # Only show success messages if wizard started successfully
        Write-Host ""
        Write-Host "================================================"
        Write-Success "Stack Masters initial setup completed!"
        Write-Host "================================================"
        Write-Host ""
        Write-Info "The Stack Masters Provisioning Wizard is now running"
        Write-Info "Use the web interface to complete your stack deployment"
        Write-Host ""
        Write-Info "Next steps:"
        Write-Host "  1. Open the provisioning wizard in your browser"
        Write-Host "  2. Select your stack configuration"
        Write-Host "  3. Follow the guided setup process"
        Write-Host ""
        Write-Info "The wizard will handle:"
        Write-Host "  - GitHub authentication"
        Write-Host "  - Repository selection and cloning"
        Write-Host "  - Environment configuration"
        Write-Host "  - Service deployment"
        Write-Host "  - SSL certificate setup"
        Write-Host ""
        Write-Info "Log file saved to: $script:LogFile"
    }
    catch {
        Write-Host ""
        Write-ErrorCustom "❌ FAILED TO START PROVISIONING WIZARD"
        Write-ErrorCustom "Error: $($_.Exception.Message)"
        Write-Host ""
        Write-Info "Troubleshooting steps:"
        Write-Host "  1. Check the log files in: $script:LogFile" -ForegroundColor White
        Write-Host "  2. Verify Node.js and npm are working: node --version && npm --version" -ForegroundColor White
        Write-Host "  3. Check if port 58217 is available: netstat -ano | findstr :58217" -ForegroundColor White
        Write-Host "  4. Try running the wizard manually:" -ForegroundColor White
        Write-Host "     cd `"$wizardDir\backend`"" -ForegroundColor Gray
        Write-Host "     npm install" -ForegroundColor Gray
        Write-Host "     node server-integrated.js" -ForegroundColor Gray
        Write-Host ""
        Write-Info "If issues persist, check the GitHub repository documentation or create an issue"
        Write-Host ""
        Write-ErrorCustom "Setup failed - wizard is not running"
        exit 1
    }
}

# Run main function with error handling
try {
    Main
}
catch {
    Write-ErrorCustom "Script failed: $($_.Exception.Message)"
    exit 1
}