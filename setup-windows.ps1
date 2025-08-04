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
    Add-Content -Path $script:LogFile -Value "[$(Get-Date)] INFO: $Message"
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    Add-Content -Path $script:LogFile -Value "[$(Get-Date)] SUCCESS: $Message"
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    Add-Content -Path $script:LogFile -Value "[$(Get-Date)] WARNING: $Message"
}

function Write-ErrorCustom { 
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    Add-Content -Path $script:LogFile -Value "[$(Get-Date)] ERROR: $Message"
}

# Initialize logging in script directory
$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrEmpty($scriptDir)) {
    # Fallback for when running interactively
    $scriptDir = (Get-Location).Path
}
$script:LogFile = Join-Path $scriptDir "stack-masters-setup.log"

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
    [int[]]$ports = @(8080, 3000, 3001, 3002, 5678, 9090, 9999, 587, 465)  # 8080 is for provisioning wizard
    
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
    
    # Source provisioning-web is included in this repository
    $sourceWizardDir = Join-Path $scriptDir "apps\provisioning-web"
    
    # Target directory for the wizard
    $targetWizardDir = "C:\StackMasters\provisioning-wizard"
    
    if (-not (Test-Path $sourceWizardDir)) {
        Write-ErrorCustom "Provisioning wizard source not found at: $sourceWizardDir"
        throw "Provisioning wizard source not found"
    }
    
    # Create StackMasters directory if it doesn't exist
    $null = New-Item -ItemType Directory -Force -Path "C:\StackMasters"
    
    if (Test-Path $targetWizardDir) {
        $backupDir = "$targetWizardDir.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "Directory $targetWizardDir already exists. Backing up to $backupDir..."
        Move-Item $targetWizardDir $backupDir
    }
    
    Write-Info "Copying provisioning wizard to $targetWizardDir..."
    try {
        Copy-Item -Path $sourceWizardDir -Destination $targetWizardDir -Recurse -Force
        Write-Success "Provisioning wizard copied successfully"
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
    
    # Navigate to backend directory
    $backendDir = Join-Path $WizardDir "backend"
    if (-not (Test-Path $backendDir)) {
        Write-ErrorCustom "Backend directory not found: $backendDir"
        throw "Backend directory not found"
    }
    
    Set-Location $backendDir
    
    Write-Info "Installing dependencies..."
    & npm install --production
    
    # Set environment variables
    # PROJECT_ROOT will be set after cloning via web wizard
    $env:PORT = "8080"
    $env:NODE_ENV = "production"
    
    # Detect environment and set HOST
    $osInfo = Get-WindowsType
    $env:HOST = if ($osInfo.Type -eq "Desktop") { "localhost" } else { "0.0.0.0" }
    
    Write-Info "Starting provisioning wizard on port 8080..."
    
    # Start the backend server in detached mode
    Write-Info "Starting Node.js server in background..."
    
    # Create a detached process that survives script termination
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = "node"
    $processStartInfo.Arguments = "server-integrated.js"
    $processStartInfo.WorkingDirectory = $backendDir
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.CreateNoWindow = $true
    $processStartInfo.RedirectStandardOutput = $false
    $processStartInfo.RedirectStandardError = $false
    
    $process = [System.Diagnostics.Process]::Start($processStartInfo)
    
    Write-Info "Provisioning wizard started with PID: $($process.Id)"
    Write-Info "Waiting for server to be ready..."
    Start-Sleep -Seconds 8
    
    # Save PID for potential cleanup
    $pidFile = Join-Path $WizardDir "wizard.pid"
    Set-Content -Path $pidFile -Value $process.Id
    
    # Test if server is accessible
    try {
        $testResponse = Invoke-WebRequest -Uri "http://localhost:8080/api/health" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($testResponse.StatusCode -eq 200) {
            Write-Success "Server is responding on port 8080 ✓"
        } else {
            Write-Warning "Server may not be fully ready yet. Check http://localhost:8080 in a moment."
        }
    } catch {
        Write-Warning "Unable to verify server status. Please check http://localhost:8080 manually."
    }
    
    # Display access information
    Write-Success "Provisioning wizard is running!"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Stack Masters Provisioning Wizard" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access the wizard at:" -ForegroundColor Yellow
    Write-Host "  http://localhost:8080" -ForegroundColor Cyan
    Write-Host ""
    
    # Get server IPs for remote access
    $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown"
    } | Select-Object -ExpandProperty IPAddress
    
    if ($ipAddresses) {
        Write-Host "From a remote machine:" -ForegroundColor Yellow
        foreach ($ip in $ipAddresses) {
            Write-Host "  http://${ip}:8080" -ForegroundColor Cyan
        }
    }
    Write-Host ""
    Write-Host "The wizard will guide you through:" -ForegroundColor Yellow
    Write-Host "  - Selecting your Stack Masters repository" -ForegroundColor White
    Write-Host "  - Configuring your environment" -ForegroundColor White
    Write-Host "  - Deploying your services" -ForegroundColor White
    Write-Host ""
}

# Repository cloning is now handled by the web wizard
# This function is kept for reference but no longer used
<#
function Clone-Repository {
    # Moved to web wizard - handled via /api/github/clone endpoint
}
#>

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
    $availableMemory = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1MB / 1024
    
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
    if (Test-PortAvailability -Port 8080 -ServiceName "Provisioning Wizard") {
        Write-Success "Port 8080 available for wizard ✓"
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

function Setup-ProvisioningWizard {
    Write-Info "Setting up Stack Masters Provisioning Wizard..."
    
    # Create wizard directory
    $wizardDir = "C:\StackMasters\provisioning-wizard"
    if (Test-Path $wizardDir) {
        Remove-Item -Path $wizardDir -Recurse -Force
    }
    New-Item -Path $wizardDir -ItemType Directory -Force | Out-Null
    
    # Copy provisioning web app
    $sourceDir = Join-Path $PSScriptRoot "apps\provisioning-web"
    if (-not (Test-Path $sourceDir)) {
        Write-ErrorCustom "Provisioning web app not found at: $sourceDir"
        throw "Provisioning web app not found"
    }
    
    Copy-Item -Path "$sourceDir\*" -Destination $wizardDir -Recurse -Force
    Write-Success "Provisioning wizard copied successfully"
    
    return $wizardDir
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
    
    # Install dependencies
    Write-Info "Installing dependencies..."
    Push-Location $backendDir
    try {
        $npmOutput = & npm install --production 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorCustom "npm install failed: $npmOutput"
            throw "npm install failed"
        }
        
        # Determine host binding
        $osInfo = Get-WindowsType
        $hostBinding = if ($osInfo.IsServer -or $Server -or ($Mode -eq "server")) { "0.0.0.0" } else { "localhost" }
        
        # Set environment variables
        $env:HOST = $hostBinding
        $env:PORT = "8080"
        $env:NODE_ENV = "production"
        
        Write-Info "Starting provisioning wizard on port 8080..."
        
        # Create process start info for proper detachment
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "node"
        $processInfo.Arguments = "server-integrated.js"
        $processInfo.WorkingDirectory = $backendDir
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        # Set environment variables for the process
        $processInfo.EnvironmentVariables["HOST"] = $hostBinding
        $processInfo.EnvironmentVariables["PORT"] = "8080"
        $processInfo.EnvironmentVariables["NODE_ENV"] = "production"
        
        # Start the detached process
        $process = [System.Diagnostics.Process]::Start($processInfo)
        Write-Info "Provisioning wizard started with PID: $($process.Id)"
        
        # Wait for server to be ready with health check
        Write-Info "Waiting for server to be ready..."
        $maxAttempts = 16  # 8 seconds total
        $attempt = 0
        $serverReady = $false
        
        do {
            Start-Sleep -Milliseconds 500
            $attempt++
            try {
                $response = Invoke-WebRequest -Uri "http://$hostBinding:8080" -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($response.StatusCode -eq 200) {
                    $serverReady = $true
                    break
                }
            }
            catch {
                # Server not ready yet, continue waiting
            }
        } while ($attempt -lt $maxAttempts)
        
        if ($serverReady) {
            Write-Success "Provisioning wizard is running!"
            Show-WizardAccessInfo -HostBinding $hostBinding
        }
        else {
            Write-Warning "Server may still be starting up. Check the process manually."
            Show-WizardAccessInfo -HostBinding $hostBinding
        }
    }
    finally {
        Pop-Location
    }
}

function Show-WizardAccessInfo {
    param([string]$HostBinding)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Stack Masters Provisioning Wizard" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Access the wizard at:" -ForegroundColor Green
    
    if ($HostBinding -eq "localhost") {
        Write-Host "  http://localhost:8080" -ForegroundColor Yellow
    }
    else {
        Write-Host "  http://localhost:8080" -ForegroundColor Yellow
        
        # Show network interfaces for remote access
        try {
            $networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" }
            if ($networkAdapters) {
                Write-Host ""
                Write-Host "From a remote machine:" -ForegroundColor Green
                foreach ($adapter in $networkAdapters) {
                    Write-Host "  http://$($adapter.IPAddress):8080" -ForegroundColor Yellow
                }
            }
        }
        catch {
            # Fallback if network detection fails
            Write-Host ""
            Write-Host "From a remote machine:" -ForegroundColor Green
            Write-Host "  http://YOUR-SERVER-IP:8080" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "The wizard will guide you through:" -ForegroundColor Cyan
    Write-Host "  - Selecting your Stack Masters repository" -ForegroundColor White
    Write-Host "  - Configuring your environment" -ForegroundColor White
    Write-Host "  - Deploying your services" -ForegroundColor White
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
    
    # Run comprehensive system validation
    Write-Info "Performing system validation..."
    if (-not (Test-SystemRequirements)) {
        Write-ErrorCustom "System validation failed. Please fix the issues and try again."
        exit 1
    }
    
    # Setup and start provisioning wizard
    $wizardDir = Setup-ProvisioningWizard
    Start-ProvisioningWizard -WizardDir $wizardDir
    
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

# Run main function with error handling
try {
    Main
}
catch {
    Write-ErrorCustom "Script failed: $($_.Exception.Message)"
    exit 1
}