# Stack Masters Windows Setup Script
# PowerShell script for preparing Windows for Stack Masters deployment

param(
    [string]$RepoUrl = "",
    [switch]$SkipAuth = $false,
    [switch]$Help = $false
)

# Script version
$VERSION = "1.1.0"

# Script-level variables for executable paths
$script:GitExePath = $null
$script:GhExePath = $null

# Check if running as Administrator immediately
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   ADMINISTRATOR PRIVILEGES REQUIRED" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This script must be run as Administrator." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Cyan
    Write-Host "  1. Close this PowerShell window" -ForegroundColor White
    Write-Host "  2. Right-click on PowerShell or Windows Terminal" -ForegroundColor White
    Write-Host "  3. Select 'Run as Administrator'" -ForegroundColor White
    Write-Host "  4. Navigate to this directory:" -ForegroundColor White
    Write-Host "     cd '$PSScriptRoot'" -ForegroundColor Yellow
    Write-Host "  5. Run the script:" -ForegroundColor White
    Write-Host "     .\setup-windows.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "DO NOT use 'sudo' or any elevation tools." -ForegroundColor Red
    Write-Host "You must start PowerShell as Administrator." -ForegroundColor Red
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    
    # Exit immediately - do not continue
    exit 1
}

# Color functions for PowerShell
function Write-Info { 
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
    try {
        Add-Content -Path $LogFile -Value "[$(Get-Date)] INFO: $Message" -ErrorAction SilentlyContinue
    } catch {}
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    try {
        Add-Content -Path $LogFile -Value "[$(Get-Date)] SUCCESS: $Message" -ErrorAction SilentlyContinue
    } catch {}
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    try {
        Add-Content -Path $LogFile -Value "[$(Get-Date)] WARNING: $Message" -ErrorAction SilentlyContinue
    } catch {}
}

function Write-Error-Custom { 
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    try {
        Add-Content -Path $LogFile -Value "[$(Get-Date)] ERROR: $Message" -ErrorAction SilentlyContinue
    } catch {}
}

# Initialize logging AFTER admin check
# Use $PSScriptRoot if available, otherwise use current directory
if ($PSScriptRoot) {
    $ScriptPath = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $ScriptPath = Get-Location
}
$LogDir = Join-Path $ScriptPath "logs"
New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue | Out-Null
$LogFile = Join-Path $LogDir "stack-masters-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Test if we can write to log file
try {
    Add-Content -Path $LogFile -Value "[$(Get-Date)] Setup script started" -ErrorAction Stop
} catch {
    # If we can't write to logs, use temp directory
    $LogDir = Join-Path $env:TEMP "stack-masters-logs"
    New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue | Out-Null
    $LogFile = Join-Path $LogDir "stack-masters-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Write-Warning "Cannot write to local logs directory. Using temp directory: $LogDir"
}

function Show-Help {
    Write-Host @"
Stack Masters Windows Setup Script v$VERSION

USAGE:
    .\setup-windows.ps1 [OPTIONS]

OPTIONS:
    -RepoUrl <string>     GitHub repository URL to clone
    -SkipAuth            Skip GitHub authentication (for testing)
    -Help                Show this help message

EXAMPLES:
    .\setup-windows.ps1
    .\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters"
    .\setup-windows.ps1 -SkipAuth

This script will install (using winget):
- Git for Windows
- Docker Desktop
- GitHub CLI
- Clone the specified repository
"@
}


function Ensure-CommandAvailable {
    # Ensure git and gh commands are available by creating wrappers if needed
    
    # Check Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        if ($script:GitExePath -and (Test-Path $script:GitExePath)) {
            function global:git { & $script:GitExePath $args }
        } else {
            # Try to find git.exe
            $gitLocations = @(
                "$env:ProgramFiles\Git\cmd\git.exe",
                "$env:ProgramFiles\Git\bin\git.exe",
                "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
                "$env:LocalAppData\Programs\Git\cmd\git.exe"
            )
            foreach ($gitPath in $gitLocations) {
                if (Test-Path $gitPath) {
                    $script:GitExePath = $gitPath
                    function global:git { & $script:GitExePath $args }
                    break
                }
            }
        }
    }
    
    # Check GitHub CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        if ($script:GhExePath -and (Test-Path $script:GhExePath)) {
            function global:gh { & $script:GhExePath $args }
        } else {
            # Try to find gh.exe
            $ghLocations = @(
                "$env:ProgramFiles\GitHub CLI\gh.exe",
                "$env:ProgramFiles\GitHub CLI\bin\gh.exe",
                "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
                "$env:LocalAppData\Programs\GitHub CLI\gh.exe"
            )
            foreach ($ghPath in $ghLocations) {
                if (Test-Path $ghPath) {
                    $script:GhExePath = $ghPath
                    function global:gh { & $script:GhExePath $args }
                    break
                }
            }
        }
    }
}

function Check-Winget {
    Write-Info "Checking for Windows Package Manager (winget)..."
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetVersion = winget --version
        Write-Success "Winget is available: $wingetVersion"
        return $true
    }
    
    Write-Error-Custom "Winget is not available on this system"
    Write-Info "Winget is included with Windows 10 1809+ and Windows 11"
    Write-Info "You can install it from the Microsoft Store as 'App Installer'"
    Write-Info "Or download from: https://github.com/microsoft/winget-cli/releases"
    return $false
}

function Install-Git {
    Write-Info "Checking for Git installation..."
    
    # Check if git is available in PATH
    $script:GitExePath = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Success "Git already installed: $gitVersion"
        $script:GitExePath = "git"
        return
    }
    
    # Check common locations for git.exe
    $gitLocations = @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:ProgramFiles\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "$env:LocalAppData\Programs\Git\cmd\git.exe"
    )
    
    foreach ($gitPath in $gitLocations) {
        if (Test-Path $gitPath) {
            $script:GitExePath = $gitPath
            $gitVersion = & $gitPath --version
            Write-Success "Git already installed: $gitVersion (found at $gitPath)"
            return
        }
    }
    
    Write-Host ""
    Write-Info "Git is not installed. Git is required for:"
    Write-Host "  - Cloning the Stack Masters repository"
    Write-Host "  - Version control and updates"
    Write-Host "  - GitHub CLI operations"
    Write-Host ""
    Write-Info "Installing Git for Windows via winget..."
    
    try {
        Write-Info "Downloading and installing Git (this may take a few minutes)..."
        # Use --disable-interactivity instead of --silent to avoid progress characters
        $null = winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        
        # Wait for installation to complete
        Write-Info "Installation complete. Locating Git executable..."
        Start-Sleep -Seconds 5
        
        # Find git.exe in common locations
        $gitLocations = @(
            "$env:ProgramFiles\Git\cmd\git.exe",
            "$env:ProgramFiles\Git\bin\git.exe",
            "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
            "$env:LocalAppData\Programs\Git\cmd\git.exe",
            "$env:ProgramFiles\Git\mingw64\bin\git.exe",
            "$env:ProgramFiles\Git\mingw32\bin\git.exe"
        )
        
        $script:GitExePath = $null
        foreach ($gitPath in $gitLocations) {
            if (Test-Path $gitPath) {
                $script:GitExePath = $gitPath
                Write-Success "Git installed successfully at: $gitPath"
                
                # Test it works
                $gitVersion = & $gitPath --version
                Write-Info "Git version: $gitVersion"
                
                # Create a function wrapper so "git" works in this session
                function global:git { & $script:GitExePath $args }
                
                return
            }
        }
        
        # If not found in standard locations, search for it
        Write-Info "Searching for Git installation..."
        $gitExe = Get-ChildItem -Path "$env:ProgramFiles" -Filter "git.exe" -Recurse -ErrorAction SilentlyContinue | 
                  Where-Object { $_.FullName -match "\\(cmd|bin)\\git\.exe$" } | 
                  Select-Object -First 1
        
        if ($gitExe) {
            $script:GitExePath = $gitExe.FullName
            Write-Success "Git installed successfully at: $($gitExe.FullName)"
            
            # Test it works
            $gitVersion = & $script:GitExePath --version
            Write-Info "Git version: $gitVersion"
            
            # Create a function wrapper
            function global:git { & $script:GitExePath $args }
        } else {
            Write-Error-Custom "Git installation completed but git.exe not found"
            Write-Info "Please restart PowerShell and run this script again"
            exit 1
        }
    }
    catch {
        Write-Error-Custom "Failed to install Git: $($_.Exception.Message)"
        Write-Info "Git is required to continue. Please install manually from: https://git-scm.com/download/win"
        exit 1
    }
}

function Install-GitHubCLI {
    Write-Info "Checking for GitHub CLI..."
    
    # Check if gh is available in PATH
    $script:GhExePath = $null
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVersion = gh --version | Select-Object -First 1
        Write-Success "GitHub CLI already installed: $ghVersion"
        $script:GhExePath = "gh"
        return
    }
    
    # Check common locations for gh.exe
    $ghLocations = @(
        "$env:ProgramFiles\GitHub CLI\gh.exe",
        "$env:ProgramFiles\GitHub CLI\bin\gh.exe",
        "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
        "$env:LocalAppData\Programs\GitHub CLI\gh.exe"
    )
    
    foreach ($ghPath in $ghLocations) {
        if (Test-Path $ghPath) {
            $script:GhExePath = $ghPath
            $ghVersion = & $ghPath --version | Select-Object -First 1
            Write-Success "GitHub CLI already installed: $ghVersion (found at $ghPath)"
            return
        }
    }
    
    Write-Host ""
    Write-Info "GitHub CLI is not installed. GitHub CLI is required for:"
    Write-Host "  - Authenticating with GitHub securely"
    Write-Host "  - Cloning private repositories"
    Write-Host "  - Managing repository access"
    Write-Host ""
    Write-Info "Installing GitHub CLI via winget..."
    
    try {
        Write-Info "Downloading and installing GitHub CLI (this may take a few minutes)..."
        # Use --disable-interactivity instead of --silent to avoid progress characters
        $null = winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        
        # Wait for installation to complete
        Write-Info "Installation complete. Locating GitHub CLI executable..."
        Start-Sleep -Seconds 5
        
        # Find gh.exe in common locations
        $ghLocations = @(
            "$env:ProgramFiles\GitHub CLI\gh.exe",
            "$env:ProgramFiles\GitHub CLI\bin\gh.exe",
            "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
            "$env:LocalAppData\Programs\GitHub CLI\gh.exe"
        )
        
        $script:GhExePath = $null
        foreach ($ghPath in $ghLocations) {
            if (Test-Path $ghPath) {
                $script:GhExePath = $ghPath
                Write-Success "GitHub CLI installed successfully at: $ghPath"
                
                # Test it works
                $ghVersion = & $ghPath --version | Select-Object -First 1
                Write-Info "GitHub CLI version: $ghVersion"
                
                # Create a function wrapper so "gh" works in this session
                function global:gh { & $script:GhExePath $args }
                
                return
            }
        }
        
        # If not found in standard locations, search for it
        Write-Info "Searching for GitHub CLI installation..."
        $ghExe = Get-ChildItem -Path "$env:ProgramFiles" -Filter "gh.exe" -Recurse -ErrorAction SilentlyContinue | 
                 Select-Object -First 1
        
        if ($ghExe) {
            $script:GhExePath = $ghExe.FullName
            Write-Success "GitHub CLI installed successfully at: $($ghExe.FullName)"
            
            # Test it works
            $ghVersion = & $script:GhExePath --version | Select-Object -First 1
            Write-Info "GitHub CLI version: $ghVersion"
            
            # Create a function wrapper
            function global:gh { & $script:GhExePath $args }
        } else {
            Write-Error-Custom "GitHub CLI installation completed but gh.exe not found"
            Write-Info "Please restart PowerShell and run this script again"
            exit 1
        }
    }
    catch {
        Write-Error-Custom "Failed to install GitHub CLI: $($_.Exception.Message)"
        Write-Info "GitHub CLI is required to continue. Please install manually from: https://cli.github.com/"
        exit 1
    }
}

function Install-Docker {
    Write-Info "Checking for Docker Desktop..."
    
    # Check if docker command exists
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = docker --version 2>$null
        Write-Success "Docker command found: $dockerVersion"
        
        # Test if Docker is actually running
        $dockerRunning = $false
        try {
            docker ps 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $dockerRunning = $true
                Write-Success "Docker is running and ready!"
                return
            }
        }
        catch {}
        
        if (-not $dockerRunning) {
            Write-Warning "Docker is installed but not running"
            Write-Host ""
            
            # Try to start Docker Desktop
            $dockerDesktopPath = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
            if (Test-Path $dockerDesktopPath) {
                Write-Info "Attempting to start Docker Desktop..."
                Start-Process $dockerDesktopPath -ErrorAction SilentlyContinue
                Write-Host "Waiting for Docker to start (this may take a minute)..." -ForegroundColor Yellow
                
                # Give Docker time to start
                $attempts = 0
                $maxAttempts = 30  # 30 seconds
                while ($attempts -lt $maxAttempts) {
                    Start-Sleep -Seconds 1
                    $attempts++
                    
                    try {
                        docker ps 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "Docker started successfully!"
                            return
                        }
                    }
                    catch {}
                    
                    if ($attempts % 5 -eq 0) {
                        Write-Host "Still waiting for Docker to start... ($attempts seconds)" -ForegroundColor DarkGray
                    }
                }
            }
            
            # Docker didn't start automatically, give user options
            Write-Warning "Docker Desktop is installed but not running"
            Write-Host ""
            Write-Host "Options:" -ForegroundColor Yellow
            Write-Host "  1. I'll start Docker manually (retry after starting)"
            Write-Host "  2. Reinstall Docker Desktop"
            Write-Host "  3. Skip Docker (warning: Stack Masters requires Docker)"
            Write-Host ""
            
            $choice = Read-Host "Select option [1-3] (default: 1)"
            if ([string]::IsNullOrEmpty($choice)) {
                $choice = "1"
            }
            
            switch ($choice) {
                "1" {
                    Write-Info "Please start Docker Desktop manually"
                    Write-Host "  1. Open Docker Desktop from Start Menu or Desktop"
                    Write-Host "  2. Wait for Docker to fully start (system tray icon)"
                    Write-Host "  3. Press Enter when ready to continue"
                    Read-Host
                    
                    # Test again
                    try {
                        docker ps 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "Docker is now running!"
                            return
                        } else {
                            Write-Error-Custom "Docker still not responding. Please ensure Docker Desktop is running."
                            exit 1
                        }
                    }
                    catch {
                        Write-Error-Custom "Docker test failed. Please ensure Docker Desktop is running."
                        exit 1
                    }
                }
                "2" {
                    Write-Info "Reinstalling Docker Desktop..."
                    # Continue to installation below
                }
                "3" {
                    Write-Warning "Skipping Docker. Stack Masters will not function without Docker!"
                    return
                }
                default {
                    Write-Warning "Invalid choice. Skipping Docker."
                    return
                }
            }
        }
    }
    
    # Check if Docker Desktop is installed but docker command not in PATH
    $dockerDesktopPath = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktopPath) {
        Write-Info "Docker Desktop found but 'docker' command not available"
        Write-Warning "Docker may need to be reinstalled or PATH updated"
    }
    
    Write-Host ""
    Write-Info "Docker Desktop is not installed. Docker is used for:"
    Write-Host "  - Running Stack Masters containers"
    Write-Host "  - Isolating application environments"
    Write-Host "  - Managing multiple stack deployments"
    Write-Host ""
    Write-Info "Attempting to install Docker Desktop..."
    Write-Warning "Note: Docker Desktop is a large download and system restart will be required"
    Write-Host ""
    
    try {
        # Enable Hyper-V and Containers features (required for Docker Desktop)
        Write-Info "Enabling Windows features for Docker (Hyper-V and Containers)..."
        $hypervResult = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart -ErrorAction SilentlyContinue
        $containersResult = Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart -ErrorAction SilentlyContinue
        
        if ($hypervResult.RestartNeeded -or $containersResult.RestartNeeded) {
            Write-Warning "System restart required after enabling Windows features"
        }
    }
    catch {
        Write-Warning "Could not enable Windows features for Docker: $($_.Exception.Message)"
        Write-Info "Docker may require manual feature enablement"
    }
    
    try {
        # Install Docker Desktop
        Write-Info "Downloading and installing Docker Desktop (this is a large download ~500MB)..."
        $null = winget install --id Docker.DockerDesktop -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        
        Write-Success "Docker Desktop installed successfully"
        Write-Warning "A system restart is required for Docker to function properly"
    }
    catch {
        Write-Warning "Docker Desktop installation failed: $($_.Exception.Message)"
        Write-Info "Docker Desktop can be installed manually later from:"
        Write-Info "https://docs.docker.com/desktop/windows/install/"
        Write-Info "The script will continue with other installations..."
    }
}


function Authenticate-GitHub {
    if ($SkipAuth) {
        Write-Info "Skipping GitHub authentication (--SkipAuth flag used)"
        return
    }
    
    Write-Info "Checking GitHub authentication status..."
    
    try {
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "GitHub CLI already authenticated!"
            
            # Show which account is logged in
            $currentUser = gh api user --jq .login 2>$null
            if ($currentUser) {
                Write-Info "Logged in as: $currentUser"
            }
            return
        }
    }
    catch {
        # Not authenticated, proceed with login
    }
    
    Write-Host ""
    Write-Warning "GitHub authentication is required"
    Write-Host ""
    Write-Info "Why authentication is needed:"
    Write-Host "  - To access private Stack Masters repositories"
    Write-Host "  - To securely clone your selected repository"
    Write-Host "  - To verify you have proper access permissions"
    Write-Host ""
    
    # Use device code authentication
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

function Get-RepositoryUrl {
    if (-not [string]::IsNullOrEmpty($RepoUrl)) {
        return $RepoUrl
    }
    
    Write-Host ""
    Write-Info "Repository Setup"
    Write-Host "Please provide the GitHub repository URL to clone."
    Write-Host ""
    Write-Warning "Note: You must be a member of the Skool community to access these repos"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  - https://github.com/AI-Stack-Master-Pros/stack-pro"
    Write-Host "    (Requires membership: https://www.skool.com/ai-stack-master-pros)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  - https://github.com/AI-Stack-Masters/stack-community"
    Write-Host "    (Requires membership: https://www.skool.com/ai-stack-masters)" -ForegroundColor DarkGray
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
    
    # Clone to stack-masters subdirectory in current location
    # Use $PSScriptRoot if available, otherwise use current directory
    if ($PSScriptRoot) {
        $ScriptPath = $PSScriptRoot
    } elseif ($script:MyInvocation.MyCommand.Path) {
        $ScriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
    } else {
        $ScriptPath = Get-Location
    }
    $cloneDir = Join-Path $ScriptPath "stack-masters"
    
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
    
    # Handle existing directory
    if (Test-Path $cloneDir) {
        Write-Warning "Directory $cloneDir already exists."
        Write-Host ""
        Write-Host "What would you like to do?" -ForegroundColor Yellow
        Write-Host "  1. Delete existing directory and clone fresh (recommended)"
        Write-Host "  2. Keep existing directory and skip cloning"
        Write-Host "  3. Cancel"
        Write-Host ""
        
        $choice = Read-Host "Select option [1-3] (default: 1)"
        if ([string]::IsNullOrEmpty($choice)) {
            $choice = "1"
        }
        
        switch ($choice) {
            "1" {
                Write-Info "Removing existing directory..."
                try {
                    # Force remove the directory
                    Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction Stop
                    Write-Success "Existing directory removed"
                }
                catch {
                    Write-Error-Custom "Failed to remove existing directory: $($_.Exception.Message)"
                    Write-Info "Please manually remove the directory and try again"
                    exit 1
                }
            }
            "2" {
                Write-Info "Keeping existing directory. Skipping clone."
                return $cloneDir
            }
            "3" {
                Write-Info "Clone cancelled by user"
                exit 0
            }
            default {
                Write-Info "Invalid choice. Using existing directory."
                return $cloneDir
            }
        }
    }
    
    # Clone the repository
    Write-Info "Cloning repository: $repoUrl"
    Write-Info "Destination: $cloneDir"
    try {
        # Ensure we clone to the exact directory we want
        gh repo clone $repoUrl "$cloneDir"
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
    
    # Test Docker - check if installed and if service is running
    $dockerNeedsRestart = $false
    try {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            Write-Info "Docker installed: $dockerVersion"
            
            # Check if Docker service is running
            try {
                docker ps 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Docker is working and ready to use!"
                } else {
                    # Docker installed but not running
                    $dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
                    if ($dockerService) {
                        if ($dockerService.Status -eq 'Running') {
                            Write-Warning "Docker service is running but Docker daemon is not responding"
                            Write-Info "Try starting Docker Desktop from the Start Menu"
                        } else {
                            Write-Warning "Docker Desktop is installed but not running"
                            Write-Info "Starting Docker Desktop..."
                            try {
                                Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
                                Write-Info "Docker Desktop is starting. Please wait a moment for it to initialize."
                                $dockerNeedsRestart = $false
                            }
                            catch {
                                Write-Warning "Could not start Docker Desktop automatically"
                                Write-Info "Please start Docker Desktop manually from the Start Menu"
                            }
                        }
                    } else {
                        Write-Warning "Docker installed but service not found - system restart may be required"
                        $dockerNeedsRestart = $true
                    }
                }
            }
            catch {
                Write-Warning "Docker installed but not accessible - may need to start Docker Desktop"
            }
        }
    }
    catch {
        Write-Warning "Docker not detected - if it was just installed, a system restart is required"
        $dockerNeedsRestart = $true
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
    Write-Host "================================================"
    Write-Host ""
    
    if ($Help) {
        Show-Help
        return
    }
    
    
    # Check what's already installed
    Write-Host ""
    Write-Info "Checking existing installations..."
    Write-Host ""
    
    $wingetInstalled = Get-Command winget -ErrorAction SilentlyContinue
    $gitInstalled = Get-Command git -ErrorAction SilentlyContinue
    $ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
    $dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue
    
    # Check GitHub auth status
    $ghAuthenticated = $false
    if ($ghInstalled -and -not $SkipAuth) {
        try {
            gh auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $ghAuthenticated = $true
            }
        }
        catch {
            # Not authenticated
        }
    }
    
    # Build list of what needs to be done
    $needsInstall = @()
    $alreadyInstalled = @()
    
    if ($wingetInstalled) {
        $alreadyInstalled += "[OK] Windows Package Manager (winget)"
    } else {
        $needsInstall += "- Windows Package Manager (winget) - REQUIRED"
    }
    
    if ($gitInstalled) {
        $gitVersion = git --version
        $alreadyInstalled += "[OK] Git ($gitVersion)"
    } else {
        $needsInstall += "- Git for Windows"
    }
    
    if ($ghInstalled) {
        $ghVersion = gh --version | Select-Object -First 1
        $alreadyInstalled += "[OK] GitHub CLI"
    } else {
        $needsInstall += "- GitHub CLI"
    }
    
    if ($dockerInstalled) {
        $dockerVersion = docker --version 2>$null
        $alreadyInstalled += "[OK] Docker ($dockerVersion)"
    } else {
        $needsInstall += "- Docker Desktop (large download, restart required)"
    }
    
    # Show status
    if ($alreadyInstalled.Count -gt 0) {
        Write-Host "Already Installed:" -ForegroundColor Green
        foreach ($item in $alreadyInstalled) {
            Write-Host "  $item" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    Write-Host "This script will perform the following:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ""
    
    if ($needsInstall.Count -gt 0) {
        Write-Host "  Software to Install:" -ForegroundColor White
        foreach ($item in $needsInstall) {
            Write-Host "    $item"
        }
        Write-Host ""
    } else {
        Write-Host "  All required software is already installed!" -ForegroundColor Green
        Write-Host ""
    }
    
    Write-Host "  System Configuration:"
    Write-Host "     - Prepare Windows environment for Stack Masters"
    Write-Host ""
    
    Write-Host "  GitHub Setup:"
    if (-not $SkipAuth) {
        if ($ghAuthenticated) {
            Write-Host "     [OK] Already authenticated with GitHub" -ForegroundColor Green
        } else {
            Write-Host "     - Authenticate with GitHub"
        }
    }
    Write-Host "     - Clone repository to .\stack-masters\"
    Write-Host ""
    
    Write-Host "  Final Steps:"
    Write-Host "     - Validate installation"
    Write-Host "     - Check system resources"
    Write-Host ""
    
    # Get confirmation
    Write-Host "Do you want to proceed with the installation?" -ForegroundColor Yellow
    $confirmation = Read-Host "Type 'yes' to continue or anything else to exit"
    
    if ($confirmation -ne 'yes') {
        Write-Warning "Installation cancelled by user"
        exit 0
    }
    
    Write-Host ""
    Write-Info "Starting Stack Masters setup..."
    Write-Info "Log file: $LogFile"
    Write-Host ""
    
    # Check for winget first
    if (-not (Check-Winget)) {
        Write-Error-Custom "Windows Package Manager (winget) is required but not available"
        Write-Info "Please install winget and run this script again"
        exit 1
    }
    
    # Install components
    Install-Git
    Install-GitHubCLI
    Install-Docker
    
    # System preparation complete
    
    # Check if Docker needs a restart before continuing
    $dockerNeedsRestart = $false
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        # Docker command exists, test if it works
        try {
            docker ps 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
                if (-not $dockerService) {
                    $dockerNeedsRestart = $true
                }
            }
        }
        catch {
            $dockerNeedsRestart = $true
        }
    } else {
        # Check if Docker was just installed
        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            $dockerNeedsRestart = $true
        }
    }
    
    # If Docker needs restart, stop here and tell user to restart
    if ($dockerNeedsRestart) {
        Clear-Host
        Write-Host "================================================"
        Write-Warning "SYSTEM RESTART REQUIRED"
        Write-Host "================================================"
        Write-Host ""
        Write-Info "Docker Desktop was installed but requires a system restart to initialize."
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Save any open work"
        Write-Host "  2. Restart your computer"
        Write-Host "  3. After restart, run this script again:"
        Write-Host ""
        Write-Host "     .\setup-windows.ps1" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  The script will:"
        Write-Host "  - Skip already installed components"
        Write-Host "  - Authenticate with GitHub (if needed)"
        Write-Host "  - Clone your repository"
        Write-Host "  - Run the environment setup"
        Write-Host ""
        Write-Host "================================================"
        Write-Host ""
        Write-Info "Log file: $LogFile"
        return
    }
    
    # Only proceed with GitHub auth and cloning if no restart is needed
    # Ensure git and gh commands are available (creates wrappers if needed)
    Ensure-CommandAvailable
    
    Authenticate-GitHub
    $cloneDir = Clone-Repository
    
    # Validate installation
    Test-Installation
    
    # Clear screen and show summary
    Clear-Host
    Write-Host "================================================"
    Write-Host "   Stack Masters Installation Summary"
    Write-Host "================================================"
    Write-Host ""
    
    # Track overall success
    $installSuccess = $true
    $dockerReady = $false
    
    # Show what was installed
    Write-Host "Installation Results:" -ForegroundColor Cyan
    Write-Host ""
    
    # Check each component
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Host "  [OK] Git: $gitVersion" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Git: Installation failed" -ForegroundColor Red
        $installSuccess = $false
    }
    
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVersion = gh --version | Select-Object -First 1
        Write-Host "  [OK] GitHub CLI: Installed" -ForegroundColor Green
        
        # Check auth status
        try {
            gh auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $currentUser = gh api user --jq .login 2>$null
                if ($currentUser) {
                    Write-Host "  [OK] GitHub Auth: Logged in as $currentUser" -ForegroundColor Green
                }
            } else {
                Write-Host "  [WARN] GitHub Auth: Not authenticated" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  [WARN] GitHub Auth: Could not verify" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] GitHub CLI: Installation failed" -ForegroundColor Red
        $installSuccess = $false
    }
    
    # Check Docker installation and status
    $dockerJustInstalled = $false
    $dockerNeedsRestart = $false
    
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = docker --version 2>$null
        Write-Host "  [OK] Docker: $dockerVersion" -ForegroundColor Green
        
        # Check if Docker is actually working
        try {
            docker ps 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Docker Status: Running and ready" -ForegroundColor Green
                $dockerReady = $true
            } else {
                # Docker command exists but not working - check why
                $dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
                if (-not $dockerService) {
                    Write-Host "  [WARN] Docker Status: Installed but service not found - RESTART REQUIRED" -ForegroundColor Yellow
                    $dockerNeedsRestart = $true
                } else {
                    Write-Host "  [WARN] Docker Status: Installed but not running" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  [WARN] Docker Status: Installed but not accessible - may need restart" -ForegroundColor Yellow
            $dockerNeedsRestart = $true
        }
    } else {
        # Check if Docker was just installed in this session
        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            Write-Host "  [WARN] Docker: Just installed - RESTART REQUIRED to initialize" -ForegroundColor Yellow
            $dockerJustInstalled = $true
            $dockerNeedsRestart = $true
        } else {
            Write-Host "  [WARN] Docker: Not installed" -ForegroundColor Yellow
        }
    }
    
    if ($cloneDir -and (Test-Path $cloneDir)) {
        Write-Host "  [OK] Repository: Cloned to $cloneDir" -ForegroundColor Green
    } elseif ($cloneDir) {
        Write-Host "  [FAIL] Repository: Clone failed" -ForegroundColor Red
        $installSuccess = $false
    } else {
        Write-Host "  [INFO] Repository: Will be cloned after Docker is ready" -ForegroundColor Cyan
    }
    
    Write-Host ""
    
    # Check system resources
    Write-Host "System Resources:" -ForegroundColor Cyan
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
    if ($freeSpace -ge 20) {
        Write-Host "  [OK] Disk Space: $($freeSpace.ToString('N1'))GB available" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Disk Space: $($freeSpace.ToString('N1'))GB (recommended: 20GB+)" -ForegroundColor Yellow
    }
    
    $totalMemory = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    if ($totalMemory -ge 4) {
        Write-Host "  [OK] Memory: $($totalMemory.ToString('N1'))GB" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Memory: $($totalMemory.ToString('N1'))GB (recommended: 4GB+)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "================================================"
    
    # Determine next steps based on Docker status
    if ($dockerNeedsRestart) {
        Write-Host ""
        Write-Host "================================================"
        Write-Warning "SYSTEM RESTART REQUIRED"
        Write-Host "================================================"
        Write-Host ""
        Write-Info "Docker Desktop was installed but requires a system restart to initialize."
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Save any open work"
        Write-Host "  2. Restart your computer"
        Write-Host "  3. After restart, run this script again:"
        Write-Host ""
        Write-Host "     .\setup-windows.ps1" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  The script will detect that everything is installed and"
        Write-Host "  automatically run the Docker initialization and environment setup."
        Write-Host ""
        Write-Info "Repository has been cloned to: $cloneDir"
    }
    elseif ($installSuccess -and $cloneDir -and (Test-Path $cloneDir)) {
        $envScript = Join-Path $cloneDir "deploy\scripts\generate-env-config.ps1"
        
        if (Test-Path $envScript) {
            if ($dockerReady) {
                Write-Host ""
                Write-Success "All components installed successfully!"
                Write-Host ""
                Write-Info "Starting environment configuration..."
                Write-Host "Running: generate-env-config.ps1"
                Write-Host ""
                Write-Host "================================================"
                Write-Host ""
                
                # Change to the repository directory and run the script
                Push-Location $cloneDir
                try {
                    & $envScript
                }
                catch {
                    Write-Error-Custom "Failed to run generate-env-config.ps1: $($_.Exception.Message)"
                    Write-Info "You can run it manually later from: $cloneDir"
                }
                finally {
                    Pop-Location
                }
            } else {
                Write-Host ""
                Write-Warning "Installation complete but Docker is not running"
                Write-Host ""
                Write-Info "Next steps:"
                Write-Host "  1. Start Docker Desktop from the Start Menu"
                Write-Host "  2. Wait for Docker to fully initialize (system tray icon)"
                Write-Host "  3. Run this script again to continue setup:"
                Write-Host ""
                Write-Host "     .\setup-windows.ps1" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Or manually navigate to: cd `"$cloneDir`""
                Write-Host "  And run: .\deploy\scripts\generate-env-config.ps1"
            }
        } else {
            Write-Host ""
            Write-Success "Installation completed!"
            Write-Host ""
            Write-Warning "Note: generate-env-config.ps1 not found in repository"
            Write-Info "Next steps:"
            Write-Host "  1. Navigate to: cd `"$cloneDir`""
            Write-Host "  2. Check the repository README for setup instructions"
        }
    } else {
        Write-Host ""
        Write-Error-Custom "Some components failed to install"
        Write-Host ""
        Write-Info "Please check the log file for details: $LogFile"
        Write-Host ""
        Write-Host "Try running the script again after addressing any errors."
    }
    
    Write-Host ""
    Write-Host "================================================"
    Write-Host ""
    Write-Info "Log file: $LogFile"
}

# Run main function
Main