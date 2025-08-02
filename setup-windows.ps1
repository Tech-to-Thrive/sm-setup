# Stack Masters Windows Server Setup Script
# PowerShell script for preparing Windows Server for containerized Stack Masters deployment

param(
    [string]$RepoUrl = "",
    [switch]$SkipFirewall = $false,
    [switch]$SkipAuth = $false,
    [switch]$Server = $false,
    [switch]$Local = $false,
    [switch]$Development = $false,
    [switch]$Help = $false
)

# Script version
$VERSION = "1.0.0"

# Color functions for PowerShell
function Write-Info { 
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value "[$(Get-Date)] INFO: $Message"
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    Add-Content -Path $LogFile -Value "[$(Get-Date)] SUCCESS: $Message"
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    Add-Content -Path $LogFile -Value "[$(Get-Date)] WARNING: $Message"
}

function Write-Error-Custom { 
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    Add-Content -Path $LogFile -Value "[$(Get-Date)] ERROR: $Message"
}

# Initialize logging
$LogFile = "C:\temp\stack-masters-setup.log"
New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

function Show-Help {
    Write-Host @"
Stack Masters Windows Server Setup Script v$VERSION

USAGE:
    .\setup-windows.ps1 [OPTIONS]

OPTIONS:
    -RepoUrl <string>     GitHub repository URL to clone
    -SkipFirewall        Skip Windows Firewall configuration
    -SkipAuth            Skip GitHub authentication (for testing)
    -Help                Show this help message

EXAMPLES:
    .\setup-windows.ps1
    .\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters"
    .\setup-windows.ps1 -SkipFirewall -SkipAuth

This script will install:
- Git for Windows
- Docker Desktop
- GitHub CLI
- Configure Windows Firewall
- Clone the specified repository
"@
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-Chocolatey {
    Write-Info "Installing Chocolatey package manager..."
    
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Info "Chocolatey already installed"
        return
    }
    
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    
    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Success "Chocolatey installed successfully"
    }
    catch {
        Write-Error-Custom "Failed to install Chocolatey: $($_.Exception.Message)"
        exit 1
    }
}

function Install-Git {
    Write-Info "Installing Git for Windows..."
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Info "Git already installed: $gitVersion"
        return
    }
    
    try {
        choco install git -y --params "/GitAndUnixToolsOnPath /NoShellIntegration"
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        Write-Success "Git installed successfully"
    }
    catch {
        Write-Error-Custom "Failed to install Git: $($_.Exception.Message)"
        exit 1
    }
}

function Install-GitHubCLI {
    Write-Info "Installing GitHub CLI..."
    
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVersion = gh --version | Select-Object -First 1
        Write-Info "GitHub CLI already installed: $ghVersion"
        return
    }
    
    try {
        choco install gh -y
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        Write-Success "GitHub CLI installed successfully"
    }
    catch {
        Write-Error-Custom "Failed to install GitHub CLI: $($_.Exception.Message)"
        exit 1
    }
}

function Install-Docker {
    Write-Info "Installing Docker Desktop..."
    
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = docker --version
        Write-Info "Docker already installed: $dockerVersion"
        return
    }
    
    try {
        # Enable Hyper-V and Containers features (required for Docker Desktop)
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
        
        # Install Docker Desktop
        choco install docker-desktop -y
        
        Write-Success "Docker Desktop installed successfully"
        Write-Warning "A system restart may be required for Docker to function properly"
    }
    catch {
        Write-Error-Custom "Failed to install Docker Desktop: $($_.Exception.Message)"
        Write-Info "Manual installation may be required from https://docs.docker.com/desktop/windows/install/"
    }
}

function Configure-Firewall {
    if ($SkipFirewall) {
        Write-Info "Skipping firewall configuration"
        return
    }
    
    # Determine deployment mode from parameters
    $deploymentMode = ""
    if ($Server) {
        $deploymentMode = "1"
    } elseif ($Local -or $Development) {
        $deploymentMode = "2"
    }
    
    # If no parameter specified, prompt user
    if ([string]::IsNullOrEmpty($deploymentMode)) {
        Write-Host ""
        Write-Info "Deployment Mode Selection"
        Write-Host "Please select your deployment type:"
        Write-Host "1) Server deployment (VPS/Cloud) - Configure firewall with required ports"
        Write-Host "2) Local development (Mac/Windows/Linux) - Skip firewall configuration"
        Write-Host ""
        
        $deploymentMode = Read-Host "Select mode [1-2] (default: 1)"
        if ([string]::IsNullOrEmpty($deploymentMode)) {
            $deploymentMode = "1"
        }
    }
    
    switch ($deploymentMode) {
        "1" {
            Write-Info "Server deployment mode selected - configuring firewall..."
            Configure-ServerFirewall
        }
        "2" {
            Write-Info "Local development mode selected - skipping firewall configuration"
            Write-Info "Assuming local firewall/router handles port access"
            return
        }
        default {
            Write-Warning "Invalid selection. Defaulting to server deployment mode."
            Configure-ServerFirewall
        }
    }
}

function Configure-ServerFirewall {
    Write-Info "Configuring Windows Firewall for server deployment..."
    
    $ports = @(80, 443, 8080, 3000, 3001, 3002, 5678, 9090, 9999, 587, 465)
    
    foreach ($port in $ports) {
        try {
            # Inbound rules
            New-NetFirewallRule -DisplayName "Stack Masters HTTP $port (Inbound)" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction SilentlyContinue
            
            # Outbound rules
            New-NetFirewallRule -DisplayName "Stack Masters HTTP $port (Outbound)" -Direction Outbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction SilentlyContinue
            
            Write-Info "Firewall rule added for port $port"
        }
        catch {
            Write-Warning "Failed to add firewall rule for port $port: $($_.Exception.Message)"
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
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "GitHub CLI already authenticated"
            return
        }
    }
    catch {
        # Not authenticated, proceed with login
    }
    
    Write-Info "GitHub authentication required for repository access"
    
    # Detect server environment (Windows Server or --Server flag)  
    $isServerEnvironment = ($Server -or (Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)
    
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
            gh auth login
            Write-Success "GitHub authentication successful"
        }
        catch {
            Write-Error-Custom "GitHub authentication failed: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        Write-Info "Desktop environment detected - opening browser for authentication"
        Write-Info "If browser doesn't open, you'll see a device code to enter at: https://github.com/login/device"
        Write-Host ""
        
        try {
            # Try browser auth first with timeout
            $job = Start-Job -ScriptBlock { gh auth login --web }
            Wait-Job $job -Timeout 30 | Out-Null
            
            if ($job.State -eq "Completed") {
                Receive-Job $job
                Write-Success "GitHub authentication successful"
            }
            else {
                Stop-Job $job
                Remove-Job $job
                Write-Info "Browser authentication timed out, using device code flow..."
                gh auth login
                Write-Success "GitHub authentication successful"
            }
        }
        catch {
            Write-Error-Custom "GitHub authentication failed: $($_.Exception.Message)"
            exit 1
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
    Write-Host "Examples:"
    Write-Host "  - https://github.com/Tech-to-Thrive/stack-masters"
    Write-Host "  - https://github.com/Tech-to-Thrive/stack-masters-pro"
    Write-Host "  - https://github.com/Tech-to-Thrive/agent-hosting"
    Write-Host ""
    
    $url = Read-Host "Repository URL"
    
    if (-not ($url -match "^https://github\.com/[^/]+/[^/]+$")) {
        Write-Error-Custom "Invalid GitHub repository URL format"
        Write-Info "Expected format: https://github.com/owner/repository"
        exit 1
    }
    
    return $url
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
            gh repo view $repoPath | Out-Null
            Write-Success "Access to repository confirmed!"
        }
        catch {
            Write-Error-Custom "Cannot access repository: $repoPath"
            Write-Info "Please ensure you have access to this repository"
            exit 1
        }
    }
    
    # Create parent directory
    New-Item -ItemType Directory -Force -Path "C:\StackMasters" | Out-Null
    
    # Remove existing directory if present
    if (Test-Path $cloneDir) {
        $backupDir = "$cloneDir.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "Directory $cloneDir already exists. Backing up to $backupDir..."
        Move-Item $cloneDir $backupDir
    }
    
    # Clone the repository
    Write-Info "Cloning repository: $repoUrl"
    try {
        gh repo clone $repoUrl $cloneDir
        Write-Success "Repository cloned to: $cloneDir"
        
        # Set environment variable for next steps
        [Environment]::SetEnvironmentVariable("STACK_MASTERS_DIR", $cloneDir, "Process")
        
        return $cloneDir
    }
    catch {
        Write-Error-Custom "Failed to clone repository: $($_.Exception.Message)"
        exit 1
    }
}

function Test-Installation {
    Write-Info "Validating installation..."
    
    $errors = @()
    
    # Test Git
    try {
        $gitVersion = git --version
        Write-Success "Git is working: $gitVersion"
    }
    catch {
        $errors += "Git test failed"
    }
    
    # Test GitHub CLI
    try {
        $ghVersion = gh --version | Select-Object -First 1
        Write-Success "GitHub CLI is working: $ghVersion"
    }
    catch {
        $errors += "GitHub CLI test failed"
    }
    
    # Test Docker (may not work until restart)
    try {
        $dockerVersion = docker --version
        Write-Success "Docker is working: $dockerVersion"
    }
    catch {
        Write-Warning "Docker test failed - may require system restart"
    }
    
    # Check disk space
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
    if ($freeSpace -lt 20) {
        Write-Warning "Low disk space: $($freeSpace.ToString('N1'))GB available (recommended: 20GB+)"
    }
    else {
        Write-Success "Disk space adequate: $($freeSpace.ToString('N1'))GB available"
    }
    
    # Check memory
    $totalMemory = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB
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
        Write-Error-Custom "Validation errors: $($errors -join ', ')"
    }
}

function Main {
    Clear-Host
    Write-Host "================================================"
    Write-Host "   Stack Masters Windows Setup Script v$VERSION"
    Write-Host "   Windows Server Preparation"
    Write-Host "================================================"
    Write-Host ""
    
    if ($Help) {
        Show-Help
        return
    }
    
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        Write-Error-Custom "This script must be run as Administrator"
        Write-Info "Please run PowerShell as Administrator and try again"
        exit 1
    }
    
    Write-Info "Starting Stack Masters setup for Windows Server..."
    Write-Info "Log file: $LogFile"
    Write-Host ""
    
    # Install components
    Install-Chocolatey
    Install-Git
    Install-GitHubCLI
    Install-Docker
    
    # Configure system
    Configure-Firewall
    
    # GitHub authentication and repository setup
    Authenticate-GitHub
    $cloneDir = Clone-Repository
    
    # Validate installation
    Test-Installation
    
    Write-Host ""
    Write-Host "================================================"
    Write-Success "Stack Masters Windows setup completed!"
    Write-Host "================================================"
    Write-Host ""
    Write-Info "Repository location: $cloneDir"
    Write-Info "Next steps:"
    Write-Host "  1. Restart the system if Docker was installed"
    Write-Host "  2. cd `"$cloneDir`""
    Write-Host "  3. Run setup scripts (if available)"
    Write-Host "  4. Configure Docker settings if needed"
    Write-Host ""
    Write-Info "Log file saved to: $LogFile"
}

# Run main function
Main