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

# Initialize logging
$script:LogFile = "C:\temp\stack-masters-setup.log"
$null = New-Item -ItemType Directory -Force -Path "C:\temp"

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
    
    [int[]]$ports = @(80, 443, 8080, 3000, 3001, 3002, 5678, 9090, 9999, 587, 465)
    
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

function Authenticate-GitHub {
    if ($SkipAuth) {
        Write-Info "Skipping GitHub authentication"
        return
    }
    
    Write-Info "Setting up GitHub authentication..."
    
    try {
        $authStatus = & gh auth status 2>&1
        if ($?) {
            Write-Success "GitHub CLI already authenticated"
            return
        }
    }
    catch {
        # Not authenticated, proceed with login
    }
    
    Write-Info "GitHub authentication required for repository access"
    
    # Detect server environment (Windows Server or --Server flag)
    $isServerEnvironment = ($Server -or (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -ne 1)
    
    if ($isServerEnvironment) {
        Write-Info "Server environment detected - using device code authentication"
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Info "GITHUB AUTHENTICATION REQUIRED"
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Info "1. GitHub will display a device code below"
        Write-Info "2. Copy the device code"
        Write-Info "3. Visit: https://github.com/login/device"
        Write-Info "4. Paste the code and complete authentication"
        Write-Host ""
        Write-Host "Starting GitHub authentication..." -ForegroundColor Green
        Write-Host ""
        
        try {
            & gh auth login
            Write-Success "GitHub authentication successful"
        }
        catch {
            Write-ErrorCustom "GitHub authentication failed: $($_.Exception.Message)"
            throw "GitHub authentication failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Info "Desktop environment detected - opening browser for authentication"
        Write-Info "If browser doesn't open, you'll see a device code to enter at: https://github.com/login/device"
        Write-Host ""
        
        try {
            # Try browser auth first with timeout
            $job = Start-Job -ScriptBlock { & gh auth login --web }
            $null = Wait-Job $job -Timeout 30
            
            if ($job.State -eq "Completed") {
                Receive-Job $job
                Write-Success "GitHub authentication successful"
            }
            else {
                Stop-Job $job
                Remove-Job $job
                Write-Info "Browser authentication timed out, using device code flow..."
                & gh auth login
                Write-Success "GitHub authentication successful"
            }
        }
        catch {
            Write-ErrorCustom "GitHub authentication failed: $($_.Exception.Message)"
            throw "GitHub authentication failed: $($_.Exception.Message)"
        }
    }
}

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
        [string]$WizardDir,
        [string]$CloneDir
    )
    
    Write-Info "Starting Stack Masters Provisioning Wizard..."
    
    # The wizard directory is already the provisioning-web directory
    if (-not (Test-Path $WizardDir)) {
        Write-ErrorCustom "Provisioning wizard directory not found: $WizardDir"
        throw "Provisioning wizard directory not found"
    }
    
    Set-Location $WizardDir
    
    # Check for different ways to run the app
    $dockerComposeFile = Join-Path $WizardDir "docker-compose.yml"
    $dockerComposeYamlFile = Join-Path $WizardDir "docker-compose.yaml"
    $dockerFile = Join-Path $WizardDir "Dockerfile"
    $packageJson = Join-Path $WizardDir "package.json"
    
    # Default port (may be overridden by docker-compose or package.json)
    $wizardPort = 8080
    
    if ((Test-Path $dockerComposeFile) -or (Test-Path $dockerComposeYamlFile)) {
        $composeFile = if (Test-Path $dockerComposeFile) { $dockerComposeFile } else { $dockerComposeYamlFile }
        Write-Info "Starting provisioning wizard with Docker Compose..."
        
        # Use docker compose (v2) or docker-compose (v1)
        $dockerComposeCmd = if (Get-Command "docker" -ErrorAction SilentlyContinue) {
            $dockerVersion = & docker compose version 2>&1
            if ($?) { "docker compose" } else { "docker-compose" }
        } else { "docker-compose" }
        
        # Set environment variables for docker-compose
        $env:CLONE_DIR = $CloneDir
        $env:PROJECT_ROOT = "/project"
        
        & $dockerComposeCmd up -d
        
        # Wait for the service to be ready
        Write-Info "Waiting for provisioning wizard to start..."
        Start-Sleep -Seconds 10
        
        # Try to extract port from docker-compose file
        $composeContent = Get-Content $composeFile -Raw
        if ($composeContent -match '(?:ports:|expose:)[\s\S]*?-\s*"?(\d+):') {
            $wizardPort = $matches[1]
        }
    }
    elseif (Test-Path $dockerFile) {
        Write-Info "Building and running provisioning wizard with Docker..."
        
        # Build the Docker image
        & docker build -t stack-masters-wizard .
        
        # Run the container with mounted repository
        & docker run -d `
            -p "${wizardPort}:${wizardPort}" `
            -v "${CloneDir}:/project:rw" `
            -v /var/run/docker.sock:/var/run/docker.sock `
            -e "PROJECT_ROOT=/project" `
            --name stack-masters-wizard `
            stack-masters-wizard
        
        Write-Info "Waiting for provisioning wizard to start..."
        Start-Sleep -Seconds 10
    }
    elseif (Test-Path $packageJson) {
        # Check if Node.js is available
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Info "Installing Node.js dependencies..."
            & npm install
            
            # Check for port in package.json scripts
            $packageContent = Get-Content $packageJson | ConvertFrom-Json
            if ($packageContent.scripts.start -match 'PORT=(\d+)') {
                $wizardPort = $matches[1]
            }
            
            Write-Info "Starting provisioning wizard with npm..."
            $env:PORT = $wizardPort
            $process = Start-Process npm -ArgumentList "start" -PassThru -WindowStyle Hidden
            Write-Info "Provisioning wizard started with PID: $($process.Id)"
            
            Write-Info "Waiting for provisioning wizard to start..."
            Start-Sleep -Seconds 5
        }
        else {
            Write-ErrorCustom "Node.js/npm not found. Please install Node.js or ensure Docker is available."
            throw "Node.js not found"
        }
    }
    else {
        Write-ErrorCustom "No suitable method found to run provisioning wizard (no docker-compose.yml, Dockerfile, or package.json)"
        throw "Cannot start provisioning wizard"
    }
    
    # Display access information
    Write-Success "Provisioning wizard is running!"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Stack Masters Provisioning Wizard" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access the wizard at:" -ForegroundColor Yellow
    Write-Host "  http://localhost:$wizardPort" -ForegroundColor Cyan
    Write-Host ""
    
    # Get server IPs for remote access
    $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown"
    } | Select-Object -ExpandProperty IPAddress
    
    if ($ipAddresses) {
        Write-Host "From a remote machine:" -ForegroundColor Yellow
        foreach ($ip in $ipAddresses) {
            Write-Host "  http://${ip}:$wizardPort" -ForegroundColor Cyan
        }
    }
    Write-Host ""
    Write-Host "The wizard will guide you through:" -ForegroundColor Yellow
    Write-Host "  - Selecting your Stack Masters repository" -ForegroundColor White
    Write-Host "  - Configuring your environment" -ForegroundColor White
    Write-Host "  - Deploying your services" -ForegroundColor White
    Write-Host ""
}

function Clone-Repository {
    $repoUrl = Get-RepositoryUrl
    
    # Extract repository name from URL
    $repoName = ($repoUrl -split '/')[-1] -replace '\.git$', ''
    $cloneDir = "C:\StackMasters\$repoName"
    
    Write-Info "Repository: $repoUrl"
    Write-Info "Clone directory: $cloneDir"
    
    # Check if user has access to the repository
    if (-not $SkipAuth) {
        try {
            $repoPath = ($repoUrl -replace 'https://github.com/', '')
            $null = & gh repo view $repoPath 2>&1
            Write-Success "Access to repository confirmed!"
        }
        catch {
            Write-ErrorCustom "Cannot access repository: $repoPath"
            Write-Info "Please ensure you have access to this repository"
            Write-Host ""
            Write-Warning "Repository access requires Skool community membership:"
            Write-Host "  - AI Stack Masters (Free): " -NoNewline -ForegroundColor Yellow
            Write-Host "https://www.skool.com/ai-stack-masters" -ForegroundColor Cyan
            Write-Host "  - AI Stack Master Pros (Paid): " -NoNewline -ForegroundColor Yellow  
            Write-Host "https://www.skool.com/ai-stack-master-pros" -ForegroundColor Cyan
            throw "Cannot access repository: $repoPath"
        }
    }
    
    # Create parent directory
    $null = New-Item -ItemType Directory -Force -Path "C:\StackMasters"
    
    # Remove existing directory if present
    if (Test-Path $cloneDir) {
        $backupDir = "$cloneDir.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "Directory $cloneDir already exists. Backing up to $backupDir..."
        Move-Item $cloneDir $backupDir
    }
    
    # Clone the repository
    Write-Info "Cloning repository: $repoUrl"
    try {
        & gh repo clone $repoUrl $cloneDir
        Write-Success "Repository cloned to: $cloneDir"
        
        # Set environment variable for next steps
        [Environment]::SetEnvironmentVariable("STACK_MASTERS_DIR", $cloneDir, "Process")
        
        return $cloneDir
    }
    catch {
        Write-ErrorCustom "Failed to clone repository: $($_.Exception.Message)"
        throw "Failed to clone repository: $($_.Exception.Message)"
    }
}

function Test-Installation {
    Write-Info "Validating installation..."
    
    $errors = New-Object System.Collections.ArrayList
    
    # Test Git
    try {
        $gitVersion = & git --version
        Write-Success "Git is working: $gitVersion"
    }
    catch {
        $null = $errors.Add("Git test failed")
    }
    
    # Test GitHub CLI
    try {
        $ghVersion = & gh --version | Select-Object -First 1
        Write-Success "GitHub CLI is working: $ghVersion"
    }
    catch {
        $null = $errors.Add("GitHub CLI test failed")
    }
    
    # Test Docker (may not work until restart)
    try {
        $dockerVersion = & docker --version
        Write-Success "Docker is working: $dockerVersion"
    }
    catch {
        Write-Warning "Docker test failed - may require system restart"
    }
    
    # Check disk space
    $freeSpace = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
    if ($freeSpace -lt 20) {
        Write-Warning "Low disk space: $($freeSpace.ToString('N1'))GB available (recommended: 20GB+)"
    }
    else {
        Write-Success "Disk space adequate: $($freeSpace.ToString('N1'))GB available"
    }
    
    # Check memory
    $totalMemory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    if ($totalMemory -lt 4) {
        Write-Warning "Low memory: $($totalMemory.ToString('N1'))GB available (recommended: 4GB+)"
    }
    else {
        Write-Success "Memory adequate: $($totalMemory.ToString('N1'))GB available"
    }
    
    if ($errors.Count -eq 0) {
        Write-Success "All validation tests passed"
    }
    else {
        Write-ErrorCustom "Validation errors: $($errors -join ', ')"
    }
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
    
    # GitHub authentication
    Authenticate-GitHub
    
    # Clone the repository
    [string]$cloneDir = Clone-Repository
    
    # Setup and start provisioning wizard
    $wizardDir = Setup-ProvisioningWizard
    Start-ProvisioningWizard -WizardDir $wizardDir -CloneDir $cloneDir
    
    # Validate installation
    Test-Installation
    
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
    Write-Host "  - Environment configuration"
    Write-Host "  - Service deployment"
    Write-Host "  - SSL certificate setup"
    Write-Host ""
    Write-Info "Repository cloned to: $cloneDir"
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