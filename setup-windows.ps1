# Stack Masters Windows Setup Script
# PowerShell script for preparing Windows for Stack Masters deployment

param(
    [string]$RepoUrl = "",
    [switch]$SkipAuth = $false,
    [switch]$Help = $false,
    [switch]$Yes = $false
)

# Script version
$VERSION = "1.2.4"

# Script-level variables for executable paths
$script:GitExePath = $null
$script:GhExePath = $null

# Check PowerShell version (require 5.1+)
if ($PSVersionTable.PSVersion.Major -lt 5 -or 
    ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host "ERROR: PowerShell 5.1 or higher is required" -ForegroundColor Red
    Write-Host "Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please upgrade PowerShell:" -ForegroundColor Cyan
    Write-Host "  Windows 10/11: Update Windows to get PowerShell 5.1+" -ForegroundColor White
    Write-Host "  Windows Server: Install Windows Management Framework 5.1" -ForegroundColor White
    Write-Host "  https://aka.ms/wmf51download" -ForegroundColor White
    exit 1
}

# Detect system architecture
function Get-SystemArchitecture {
    # Multiple methods to ensure accurate detection
    $arch = $null
    
    # Method 1: Environment variable (most reliable)
    if ($env:PROCESSOR_ARCHITECTURE) {
        switch ($env:PROCESSOR_ARCHITECTURE) {
            "AMD64" { $arch = "x64" }
            "x86" { 
                # Check if running 32-bit PS on 64-bit OS
                if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
                    $arch = "x64"
                } else {
                    $arch = "x86"
                }
            }
            "ARM64" { $arch = "ARM64" }
            "ARM" { $arch = "ARM" }
        }
    }
    
    # Method 2: WMI as fallback
    if (-not $arch) {
        try {
            $processor = Get-WmiObject Win32_Processor | Select-Object -First 1
            switch ($processor.Architecture) {
                0 { $arch = "x86" }
                1 { $arch = "MIPS" }
                2 { $arch = "Alpha" }
                3 { $arch = "PowerPC" }
                5 { $arch = "ARM" }
                6 { $arch = "ia64" }
                9 { $arch = "x64" }
                12 { $arch = "ARM64" }
            }
        } catch {
            # WMI might fail in some environments
        }
    }
    
    # Method 3: Check system info
    if (-not $arch) {
        if ([System.IntPtr]::Size -eq 8) {
            $arch = "x64"  # 64-bit process
        } elseif ([System.IntPtr]::Size -eq 4) {
            $arch = "x86"  # 32-bit process
        }
    }
    
    # Default to x64 if detection fails
    if (-not $arch) {
        $arch = "x64"
    }
    
    return $arch
}

# Get OS version info
function Get-WindowsVersion {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $version = [System.Environment]::OSVersion.Version
    
    $info = @{
        Name = $os.Caption
        Version = $os.Version
        Build = $version.Build
        Architecture = Get-SystemArchitecture
        IsServer = $os.ProductType -eq 3
        IsWindows10 = $version.Major -eq 10 -and $version.Build -lt 22000
        IsWindows11 = $version.Major -eq 10 -and $version.Build -ge 22000
        IsServer2022 = $os.Caption -like "*Server 2022*"
        IsServer2025 = $os.Caption -like "*Server 2025*"
    }
    
    return $info
}

# Store system info globally
$script:SystemInfo = Get-WindowsVersion

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

# Initialize logging and state tracking AFTER admin check
# Always use a safe location for logs that won't be deleted during setup
$StateDir = Join-Path $env:APPDATA "StackMasters"
$LogDir = Join-Path $StateDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue | Out-Null

# Fallback to temp if AppData isn't writable
if (-not (Test-Path $LogDir)) {
    $StateDir = Join-Path $env:TEMP "stack-masters-state"
    $LogDir = Join-Path $env:TEMP "stack-masters-logs"
    New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction SilentlyContinue | Out-Null
}

$LogFile = Join-Path $LogDir "stack-masters-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$StateFile = Join-Path $StateDir "setup-state.json"

# State management functions
function Save-State {
    param(
        [string]$Key,
        [string]$Value
    )
    
    try {
        $state = @{}
        if (Test-Path $StateFile) {
            # PowerShell 5.1 compatible - convert to PSCustomObject first
            $jsonObj = Get-Content $StateFile -Raw | ConvertFrom-Json
            # Convert PSCustomObject to hashtable
            $jsonObj.PSObject.Properties | ForEach-Object {
                $state[$_.Name] = $_.Value
            }
        }
        $state[$Key] = $Value
        $state | ConvertTo-Json | Set-Content $StateFile -Force
    } catch {
        # State tracking is optional, don't fail if it doesn't work
    }
}

function Get-State {
    param([string]$Key)
    
    try {
        if (Test-Path $StateFile) {
            # PowerShell 5.1 compatible
            $jsonObj = Get-Content $StateFile -Raw | ConvertFrom-Json
            return $jsonObj.$Key
        }
    } catch {
        return $null
    }
    return $null
}

function Clear-State {
    try {
        if (Test-Path $StateFile) {
            # Use progress-safe removal for state file
            $oldPref = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Remove-Item $StateFile -Force
            }
            finally {
                $ProgressPreference = $oldPref
            }
        }
    } catch {
        # Optional operation
    }
}

# Progress tracking
$script:StepsTotal = 7
$script:StepCurrent = 0

function Show-Progress {
    param([string]$StepName)
    
    $script:StepCurrent++
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Step $($script:StepCurrent) of $($script:StepsTotal): $StepName" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Save-State "current_step" $script:StepCurrent
    Save-State "current_step_name" $StepName
}

# Test if we can write to log file
try {
    Add-Content -Path $LogFile -Value "[$(Get-Date)] Setup script started" -ErrorAction Stop
    Add-Content -Path $LogFile -Value "[$(Get-Date)] System: $($script:SystemInfo.Name) $($script:SystemInfo.Architecture)" -ErrorAction Stop
} catch {
    # Final fallback
    $LogFile = Join-Path $env:TEMP "stack-masters-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Write-Warning "Cannot write to AppData logs directory. Using temp: $LogFile"
}

function Show-Help {
    Write-Host @"
Stack Masters Windows Setup Script v$VERSION

USAGE:
    .\setup-windows.ps1 [OPTIONS]

OPTIONS:
    -RepoUrl <string>     GitHub repository URL to clone
    -SkipAuth            Skip GitHub authentication (for testing)
    -Yes                 Auto-confirm installation (skip confirmation prompt)
    -Help                Show this help message

EXAMPLES:
    .\setup-windows.ps1
    .\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters"
    .\setup-windows.ps1 -SkipAuth
    .\setup-windows.ps1 -Yes

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

# Normalize GitHub URL to standard format
function Normalize-GitHubUrl {
    param([string]$Url)
    
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }
    
    # Trim whitespace
    $Url = $Url.Trim()
    
    # Remove trailing slashes
    $Url = $Url.TrimEnd('/')
    
    # Handle various GitHub URL formats
    # Examples:
    # - github.com/owner/repo
    # - https://github.com/owner/repo
    # - http://github.com/owner/repo
    # - git@github.com:owner/repo.git
    # - git@github.com:owner/repo
    # - https://github.com/owner/repo.git
    # - https://github.com/owner/repo/
    # - https://github.com/owner/repo/tree/main
    
    # Extract owner and repo using regex patterns
    $owner = $null
    $repo = $null
    
    # Pattern 1: SSH format (git@github.com:owner/repo.git or git@github.com:owner/repo)
    if ($Url -match '^git@github\.com:([^/]+)/([^/\.]+)(\.git)?/?.*$') {
        $owner = $Matches[1]
        $repo = $Matches[2]
    }
    # Pattern 2: HTTPS/HTTP format with or without protocol
    elseif ($Url -match '^(https?://)?github\.com/([^/]+)/([^/\.]+)(\.git)?/?.*$') {
        $owner = $Matches[2]
        $repo = $Matches[3]
    }
    # Pattern 3: Just owner/repo
    elseif ($Url -match '^([^/]+)/([^/\.]+)(\.git)?/?.*$') {
        $owner = $Matches[1]
        $repo = $Matches[2]
    }
    
    # If we successfully extracted owner and repo, build the normalized URL
    if ($owner -and $repo) {
        # Remove any trailing .git from repo name
        $repo = $repo -replace '\.git$', ''
        
        # Build standard HTTPS URL
        return "https://github.com/$owner/$repo"
    }
    
    # If no pattern matched, return null
    return $null
}

function Get-RepositoryUrl {
    if (-not [string]::IsNullOrEmpty($RepoUrl)) {
        # Normalize the provided URL
        $normalizedUrl = Normalize-GitHubUrl -Url $RepoUrl
        if (-not $normalizedUrl) {
            Write-Error-Custom "Invalid GitHub repository URL format: $RepoUrl"
            Write-Info "Expected format: https://github.com/owner/repository"
            exit 1
        }
        Save-State "last_repo_url" $normalizedUrl
        Save-State "repo_type" "custom"
        return $normalizedUrl
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Info "REPOSITORY SETUP"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please select which repository you want to clone:" -ForegroundColor White
    Write-Host ""
    Write-Warning "Note: You must be a member of the appropriate Skool community to access these repositories"
    Write-Host ""
    Write-Host "Available Options:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Stack Masters Community (Free)" -ForegroundColor Green
    Write-Host "     Repository: https://github.com/AI-Stack-Masters/stack-community" -ForegroundColor DarkGray
    Write-Host "     Membership: https://www.skool.com/ai-stack-masters" -ForegroundColor DarkGray
    Write-Host "     Access: Free Skool community membership required" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2. Stack Masters Pro (Paid)" -ForegroundColor Yellow
    Write-Host "     Repository: https://github.com/AI-Stack-Master-Pros/stack-pro" -ForegroundColor DarkGray
    Write-Host "     Membership: https://www.skool.com/ai-stack-master-pros" -ForegroundColor DarkGray
    Write-Host "     Access: Paid Skool community membership required" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3. Custom Repository" -ForegroundColor Cyan
    Write-Host "     Enter your own GitHub repository URL" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Enter your choice [1-3] (default: 1)"

    if ([string]::IsNullOrEmpty($choice)) {
        $choice = "1"
    }

    $normalizedUrl = $null
    $repoType = "custom"

    switch ($choice) {
        "1" {
            $normalizedUrl = "https://github.com/AI-Stack-Masters/stack-community"
            $repoType = "free"
            Write-Success "Selected: Stack Masters Community (Free)"
        }
        "2" {
            $normalizedUrl = "https://github.com/AI-Stack-Master-Pros/stack-pro"
            $repoType = "pro"
            Write-Success "Selected: Stack Masters Pro (Paid)"
            Write-Host ""
            Write-Warning "Pro repository requires an active paid membership at:"
            Write-Host "https://www.skool.com/ai-stack-master-pros" -ForegroundColor Yellow
        }
        "3" {
            Write-Host ""
            Write-Info "Enter custom repository URL"
            Write-Host ""
            Write-Info "Supported formats:"
            Write-Host "  - https://github.com/owner/repository"
            Write-Host "  - github.com/owner/repository"
            Write-Host "  - git@github.com:owner/repository.git"
            Write-Host "  - owner/repository"
            Write-Host ""

            $url = Read-Host "Repository URL"
            $normalizedUrl = Normalize-GitHubUrl -Url $url

            if (-not $normalizedUrl) {
                Write-Error-Custom "Invalid GitHub repository URL format: $url"
                exit 1
            }

            Write-Success "Normalized URL: $normalizedUrl"
            $repoType = "custom"
        }
        default {
            Write-Error-Custom "Invalid choice: $choice"
            Write-Info "Please run the script again and select 1, 2, or 3"
            exit 1
        }
    }

    Write-Host ""

    # Save for recovery and error handling
    Save-State "last_repo_url" $normalizedUrl
    Save-State "repo_type" $repoType

    return $normalizedUrl
}

function Prompt-CloneDirectory {
    param([string]$RepoName)
    
    # Use system-wide location for Docker containers
    # ProgramData is the correct location for application data that needs to be accessible system-wide
    $systemDir = "C:\ProgramData\StackMasters"
    $userDir = Join-Path $env:USERPROFILE "stack-masters"
    $currentDir = Get-Location
    
    Write-Host ""
    Write-Info "Repository Clone Location"
    Write-Host ""
    Write-Host "Where would you like to clone the repository?"
    Write-Host ""
    Write-Host "Important: Since Docker runs system-wide, choose an appropriate location." -ForegroundColor Yellow
    Write-Host "For production use, option 1 (system-wide) is strongly recommended." -ForegroundColor Blue
    Write-Host ""
    Write-Host "Repository name: $RepoName" -ForegroundColor Cyan
    Write-Host "Current directory: $currentDir"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  1. $systemDir (recommended - system-wide, all users)" -ForegroundColor Green
    Write-Host "  2. $userDir (user-specific, won't work for other users)" -ForegroundColor Yellow
    Write-Host "  3. $currentDir (current directory)"
    Write-Host "  4. Custom path"
    Write-Host ""
    
    $choice = Read-Host "Enter choice [1-4] or custom path (default: 1)"
    
    $cloneBaseDir = switch ($choice) {
        { $_ -eq "1" -or [string]::IsNullOrEmpty($_) } { 
            # System-wide location - requires admin rights (which we already have)
            $systemDir 
        }
        "2" { 
            Write-Warning "User-specific location selected. Docker containers may not be accessible to other users or system services."
            Write-Host "Press Enter to continue or Ctrl+C to cancel..." -ForegroundColor Yellow
            Read-Host
            $userDir 
        }
        "3" { $currentDir }
        "4" { 
            $customPath = Read-Host "Enter custom path"
            $customPath
        }
        default { $choice }
    }
    
    # Expand environment variables and resolve path
    $cloneBaseDir = [System.Environment]::ExpandEnvironmentVariables($cloneBaseDir)
    $cloneBaseDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($cloneBaseDir)
    
    # Set final clone directory
    $cloneDir = Join-Path $cloneBaseDir $RepoName
    
    # Check if using system directory and provide Docker volume guidance
    if ($cloneBaseDir -match "^C:\\ProgramData" -or $cloneBaseDir -match "^C:\\Program Files") {
        Write-Info "System-wide directory selected. This is the recommended choice for Docker deployments."
        Write-Host ""
        Write-Host "Note: Docker Desktop will need permission to access this directory." -ForegroundColor Cyan
        Write-Host "This is typically configured automatically." -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Validate and create parent directory
    Validate-AndCreateDirectory -Directory $cloneBaseDir
    
    return $cloneDir
}

function Validate-AndCreateDirectory {
    param([string]$Directory)
    
    try {
        if (Test-Path $Directory) {
            # Check if directory is writable
            $testFile = Join-Path $Directory "test_write_permissions.tmp"
            try {
                [System.IO.File]::WriteAllText($testFile, "test")
                # Progress-safe removal
                $oldPref = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                try {
                    Remove-Item $testFile -Force
                }
                finally {
                    $ProgressPreference = $oldPref
                }
                Write-Info "Using existing directory: $Directory"
            }
            catch {
                Write-Error-Custom "Directory $Directory is not writable"
                Write-Info "Please choose a different location or check permissions"
                exit 1
            }
        }
        else {
            # Check if parent directory exists and is writable
            $parentDir = Split-Path $Directory -Parent
            if (-not (Test-Path $parentDir)) {
                Write-Error-Custom "Parent directory $parentDir does not exist"
                Write-Info "Please choose a different location"
                exit 1
            }
            
            # Try to create the directory
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            Write-Success "Created directory: $Directory"
        }
    }
    catch {
        Write-Error-Custom "Failed to create or access directory: $Directory"
        Write-Info "Error: $($_.Exception.Message)"
        exit 1
    }
}

# Helper function: Safe directory removal with retry logic
function Safe-RemoveDirectory {
    param(
        [string]$Directory,
        [int]$MaxRetries = 3
    )
    
    $retryDelay = 2
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Info "Attempting to remove directory (attempt $i/$MaxRetries)..."
        
        try {
            # Save current progress preference and disable progress bar
            $oldProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            
            try {
                # First, try normal removal with force
                Remove-Item -Path $Directory -Recurse -Force -ErrorAction Stop
            }
            finally {
                # Restore progress preference
                $ProgressPreference = $oldProgressPreference
                
                # Clear any lingering progress bar by writing spaces and returning cursor
                Write-Host "`r$(' ' * 120)`r" -NoNewline
            }
            
            # Verify it's actually gone
            if (-not (Test-Path $Directory)) {
                Write-Success "Directory removed successfully"
                return $true
            }
        }
        catch {
            Write-Warning "Directory removal failed: $($_.Exception.Message)"
        }
        
        # If we're here, removal failed - try recovery strategies
        Write-Warning "Attempting recovery strategies..."
        
        # Strategy 1: Close file handles (requires handle.exe or similar)
        # For now, we'll ask user to close programs
        if ($i -eq 1) {
            Write-Warning "Directory may be in use by another program"
            Write-Host "Please close any programs that might be using files in:" -ForegroundColor Yellow
            Write-Host "  $Directory" -ForegroundColor Yellow
            Write-Host ""
        }
        
        # Strategy 2: Try to rename first (sometimes helps with locked files)
        try {
            $tempName = "$Directory.removing"
            Rename-Item -Path $Directory -NewName $tempName -Force -ErrorAction SilentlyContinue
            
            # Save current progress preference and disable progress bar
            $oldProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            
            try {
                Remove-Item -Path $tempName -Recurse -Force -ErrorAction SilentlyContinue
            }
            finally {
                # Restore progress preference
                $ProgressPreference = $oldProgressPreference
                
                # Clear any lingering progress bar
                Write-Host "`r$(' ' * 120)`r" -NoNewline
            }
            
            if (-not (Test-Path $Directory) -and -not (Test-Path $tempName)) {
                Write-Success "Directory removed using rename strategy"
                return $true
            }
        }
        catch {
            # Rename strategy failed, continue
        }
        
        # Check if directory still exists
        if (-not (Test-Path $Directory)) {
            Write-Success "Directory removed successfully"
            return $true
        }
        
        # If still here, wait before retry
        if ($i -lt $MaxRetries) {
            Write-Warning "Waiting $retryDelay seconds before retry..."
            Start-Sleep -Seconds $retryDelay
            $retryDelay *= 2  # Exponential backoff
        }
    }
    
    # All retries failed
    Write-Error-Custom "Failed to remove directory after $MaxRetries attempts"
    Write-Info "Manual intervention required. Please try:"
    Write-Host "  1. Close any programs using files in: $Directory" -ForegroundColor Yellow
    Write-Host "  2. Check folder permissions" -ForegroundColor Yellow
    Write-Host "  3. Run manually: Remove-Item -Path ""$Directory"" -Recurse -Force" -ForegroundColor Yellow
    Write-Host "  4. Or delete the folder using File Explorer" -ForegroundColor Yellow
    return $false
}

# Helper function: Clone with retry logic
function Clone-WithRetry {
    param(
        [string]$RepoUrl,
        [string]$CloneDir,
        [int]$MaxRetries = 3
    )
    
    $retryDelay = 2
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Info "Cloning repository (attempt $i/$MaxRetries)..."
        
        # Clear any partial clone
        if (Test-Path $CloneDir) {
            Write-Warning "Partial clone detected, cleaning up..."
            if (-not (Safe-RemoveDirectory -Directory $CloneDir)) {
                return $false
            }
        }
        
        # Attempt clone
        try {
            Write-Info "Starting clone operation. This may take several minutes for large repositories..."
            Write-Host ""
            
            # Run clone and let user see the progress
            # We'll capture stderr only if it fails
            $errorOutput = $null
            gh repo clone $RepoUrl "$CloneDir"
            $cloneExitCode = $LASTEXITCODE
            
            # If clone failed, capture the error for analysis
            if ($cloneExitCode -ne 0) {
                # Try to get the last error message
                $errorOutput = $Error[0].ToString()
            }
            
            Write-Host ""  # Add spacing after clone output
            
            # Verify clone actually succeeded with multiple checks
            if ($cloneExitCode -eq 0) {
                # Check for .git directory
                if (Test-Path "$CloneDir\.git") {
                    # Additional verification - check if git recognizes it as a valid repo
                    Push-Location $CloneDir
                    try {
                        $gitStatus = git status 2>&1
                        $gitExitCode = $LASTEXITCODE
                        
                        if ($gitExitCode -eq 0) {
                            # Final check - ensure there are actual files
                            $fileCount = (Get-ChildItem -Path . -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
                            if ($fileCount -gt 0) {
                                Write-Success "Repository cloned successfully"
                                return $true
                            }
                            else {
                                Write-Warning "Clone appeared to succeed but no files found in repository"
                            }
                        }
                        else {
                            Write-Warning "Clone appeared to succeed but git status failed: $gitStatus"
                        }
                    }
                    finally {
                        Pop-Location
                    }
                }
                else {
                    Write-Warning "Clone reported success but .git directory not found"
                }
            }
            
            # If we get here, clone failed
            if ($errorOutput) {
                Write-Warning "Clone failed with error: $errorOutput"
            } else {
                Write-Warning "Clone failed (check output above for details)"
            }
            
            # Check for SSL errors specifically
            if ($errorOutput -match "SSL|decryption failed|bad record mac") {
                Write-Warning "SSL/TLS error detected. This could be caused by:"
                Write-Host "  - Corporate proxy or firewall" -ForegroundColor Yellow
                Write-Host "  - Antivirus software intercepting SSL" -ForegroundColor Yellow  
                Write-Host "  - Network connectivity issues" -ForegroundColor Yellow
                Write-Host "  - Git SSL configuration" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Try running: git config --global http.sslVerify false" -ForegroundColor Cyan
                Write-Host "Note: Only use this temporarily for testing!" -ForegroundColor Red
            }
        }
        catch {
            Write-Warning "Clone failed: $($_.Exception.Message)"
        }
        
        # Check for common issues
        try {
            gh auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error-Custom "GitHub authentication lost. Please run: gh auth login"
                return $false
            }
        }
        catch {
            Write-Warning "Could not verify GitHub authentication"
        }
        
        # Check network connectivity
        try {
            $ping = Test-Connection -ComputerName "github.com" -Count 1 -Quiet
            if (-not $ping) {
                Write-Warning "Network connectivity issue detected"
            }
        }
        catch {
            Write-Warning "Could not test network connectivity"
        }
        
        # Wait before retry
        if ($i -lt $MaxRetries) {
            Write-Info "Waiting $retryDelay seconds before retry..."
            Start-Sleep -Seconds $retryDelay
            $retryDelay *= 2
        }
    }
    
    # All retries failed
    Write-Error-Custom "Failed to clone repository after $MaxRetries attempts"
    Write-Info "Please check:"
    Write-Host "  1. Network connectivity: ping github.com" -ForegroundColor Yellow
    Write-Host "  2. GitHub authentication: gh auth status" -ForegroundColor Yellow
    Write-Host "  3. Repository access: gh repo view $RepoUrl" -ForegroundColor Yellow
    Write-Host "  4. Disk space: Get-PSDrive C" -ForegroundColor Yellow
    return $false
}

function Clone-Repository {
    $repoUrl = Get-RepositoryUrl

    # Save state for recovery
    Save-State -Key "last_repo_url" -Value $repoUrl

    # Extract repository info from normalized URL (https://github.com/owner/repo)
    # Since URL is normalized, we can use simple extraction
    $repoPath = $repoUrl -replace 'https://github.com/', ''  # Remove prefix
    $repoParts = $repoPath -split '/', 2                     # Split into owner and repo
    $repoOwner = $repoParts[0]
    $repoName = $repoParts[1]

    Write-Info "Repository: $repoPath"

    # Prompt user for clone directory
    $cloneDir = Prompt-CloneDirectory -RepoName $repoName

    Write-Info "Clone directory: $cloneDir"

    # Check if user has access to the repository
    if (-not $SkipAuth) {
        try {
            gh repo view $repoPath | Out-Null
            Write-Success "Access to repository confirmed!"
        }
        catch {
            Write-Error-Custom "Cannot access repository: $repoPath"
            Write-Host ""

            # Get the repository type from state
            $repoType = Get-State "repo_type"

            if ($repoType -eq "pro") {
                # Pro repository access failed
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host "   PRO MEMBERSHIP REQUIRED" -ForegroundColor Red
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host ""
                Write-Warning "The Stack Masters Pro repository requires an active paid membership."
                Write-Host ""
                Write-Host "To access the Pro repository:" -ForegroundColor Cyan
                Write-Host "  1. Join the paid Skool community at:" -ForegroundColor White
                Write-Host "     https://www.skool.com/ai-stack-master-pros" -ForegroundColor Yellow
                Write-Host "  2. Complete your payment" -ForegroundColor White
                Write-Host "  3. Confirm your GitHub username was entered correctly when you joined" -ForegroundColor White
                Write-Host "     (If incorrect, ask a community admin for help to update it)" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "If you recently joined and don't have access yet:" -ForegroundColor Cyan
                Write-Host "  1. Check your EMAIL INBOX for a GitHub organization invitation" -ForegroundColor White
                Write-Host "     (The invitation comes from GitHub, not Skool)" -ForegroundColor DarkGray
                Write-Host "  2. Accept the invitation to join the repository" -ForegroundColor White
                Write-Host ""
                Write-Host "Still no invitation? Get help:" -ForegroundColor Cyan
                Write-Host "  - Post in the Skool community using the 'Onboarding Help' category:" -ForegroundColor White
                Write-Host "    https://www.skool.com/ai-stack-master-pros" -ForegroundColor Yellow
                Write-Host "  - Include your GitHub username in your post" -ForegroundColor White
                Write-Host ""
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host ""
                Write-Host "Would you like to try the free version instead?" -ForegroundColor Yellow
                $retry = Read-Host "Type 'yes' to use Stack Masters Community (Free), or anything else to exit"

                # Accept y, Y, yes, Yes, YES, etc. (case-insensitive yes confirmation)
                # Pattern: ^[Yy]([Ee][Ss])?$ matches y|Y|yes|Yes|YES|yEs|yeS|YeS|yES|YEs
                if ($retry -match '^[Yy]([Ee][Ss])?$') {
                    Write-Host ""
                    Write-Info "Switching to Stack Masters Community (Free)..."
                    $script:RepoUrl = "https://github.com/AI-Stack-Masters/stack-community"
                    Save-State "last_repo_url" $script:RepoUrl
                    Save-State "repo_type" "free"
                    # Recursively call Clone-Repository with the new URL
                    return Clone-Repository
                } else {
                    Write-Info "Installation cancelled"
                    exit 0
                }
            } elseif ($repoType -eq "free") {
                # Free repository access failed
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host "   COMMUNITY MEMBERSHIP REQUIRED" -ForegroundColor Red
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host ""
                Write-Warning "The Stack Masters Community repository requires a free Skool membership."
                Write-Host ""
                Write-Host "To access the Community repository:" -ForegroundColor Cyan
                Write-Host "  1. Join the free Skool community at:" -ForegroundColor White
                Write-Host "     https://www.skool.com/ai-stack-masters" -ForegroundColor Yellow
                Write-Host "  2. Confirm your GitHub username was entered correctly when you joined" -ForegroundColor White
                Write-Host "     (If incorrect, ask a community admin for help to update it)" -ForegroundColor DarkGray
                Write-Host "  3. Check your EMAIL INBOX for a GitHub organization invitation" -ForegroundColor White
                Write-Host "     (The invitation comes from GitHub, not Skool)" -ForegroundColor DarkGray
                Write-Host "  4. Accept the invitation to join the repository" -ForegroundColor White
                Write-Host ""
                Write-Host "Still no invitation? Get help:" -ForegroundColor Cyan
                Write-Host "  - Post in the Skool community using the 'Onboarding Help' category:" -ForegroundColor White
                Write-Host "    https://www.skool.com/ai-stack-masters" -ForegroundColor Yellow
                Write-Host "  - Include your GitHub username in your post" -ForegroundColor White
                Write-Host ""
                Write-Host "==========================================" -ForegroundColor Red
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  1. Retry (after joining and accepting the GitHub invitation)"
                Write-Host "  2. Re-authenticate GitHub (gh auth login)"
                Write-Host "  3. Exit"
                Write-Host ""
                $retryChoice = Read-Host "Select option [1-3] (default: 3)"
                if ([string]::IsNullOrEmpty($retryChoice)) { $retryChoice = "3" }

                switch ($retryChoice) {
                    "1" {
                        Write-Info "Retrying repository access..."
                        return Clone-Repository
                    }
                    "2" {
                        Write-Info "Re-authenticating with GitHub..."
                        gh auth login
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "GitHub authentication successful!"
                            return Clone-Repository
                        } else {
                            Write-Error-Custom "GitHub authentication failed"
                            Read-Host "Press Enter to exit"
                            exit 1
                        }
                    }
                    default {
                        Write-Info "Installation cancelled"
                        Read-Host "Press Enter to exit"
                        exit 1
                    }
                }
            } else {
                # Custom repository access failed
                Write-Info "Please ensure:"
                Write-Host "  1. You have access to this repository" -ForegroundColor White
                Write-Host "  2. Your GitHub authentication is working: gh auth status" -ForegroundColor White
                Write-Host "  3. The repository URL is correct" -ForegroundColor White

                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  1. Retry (after verifying access)"
                Write-Host "  2. Re-authenticate GitHub (gh auth login)"
                Write-Host "  3. Enter a different repository URL"
                Write-Host "  4. Exit"
                Write-Host ""
                $retryChoice = Read-Host "Select option [1-4] (default: 4)"
                if ([string]::IsNullOrEmpty($retryChoice)) { $retryChoice = "4" }

                switch ($retryChoice) {
                    "1" {
                        Write-Info "Retrying repository access..."
                        return Clone-Repository
                    }
                    "2" {
                        Write-Info "Re-authenticating with GitHub..."
                        gh auth login
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "GitHub authentication successful!"
                            return Clone-Repository
                        } else {
                            Write-Error-Custom "GitHub authentication failed"
                            Read-Host "Press Enter to exit"
                            exit 1
                        }
                    }
                    "3" {
                        Write-Host ""
                        $newUrl = Read-Host "Enter the repository URL"
                        if (-not [string]::IsNullOrEmpty($newUrl)) {
                            # Update the script-level RepoUrl so Get-RepositoryUrl uses it
                            $script:RepoUrl = $newUrl
                            Write-Info "Retrying with new repository URL..."
                            return Clone-Repository
                        } else {
                            Write-Error-Custom "No URL provided"
                            Read-Host "Press Enter to exit"
                            exit 1
                        }
                    }
                    default {
                        Write-Info "Installation cancelled"
                        Read-Host "Press Enter to exit"
                        exit 1
                    }
                }
            }
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
                if (Safe-RemoveDirectory -Directory $cloneDir) {
                    # Directory removed successfully, continue with clone
                }
                else {
                    Write-Error-Custom "Failed to remove existing directory"
                    Write-Host ""
                    Write-Host "Recovery options:" -ForegroundColor Yellow
                    Write-Host "  1. Fix the issue manually and re-run the script" -ForegroundColor White
                    Write-Host "  2. Choose a different directory when prompted" -ForegroundColor White
                    Write-Host "  3. Run the script from a different location" -ForegroundColor White
                    Write-Host ""
                    Read-Host "Press Enter to exit and try again"
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
    
    # Clone the repository with retry logic
    Write-Info "Starting repository clone process..."
    if (Clone-WithRetry -RepoUrl $repoUrl -CloneDir $cloneDir) {
        Write-Success "Repository successfully cloned to: $cloneDir"
        
        # Set environment variable for next steps
        [Environment]::SetEnvironmentVariable("STACK_MASTERS_DIR", $cloneDir, "Process")
        
        # Save state for recovery
        Save-State "last_clone_dir" $cloneDir
        
        return $cloneDir
    }
    else {
        Write-Error-Custom "Repository cloning failed"
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Fix any issues mentioned above" -ForegroundColor White
        Write-Host "  2. Re-run this script: .\setup-windows.ps1" -ForegroundColor White
        Write-Host "  3. Or manually clone: gh repo clone $repoUrl ""$cloneDir""" -ForegroundColor White
        Write-Host ""
        Write-Host "For help, check the log file: $LogFile" -ForegroundColor Cyan
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
    Write-Info "System: $($script:SystemInfo.Name)"
    Write-Info "Architecture: $($script:SystemInfo.Architecture)"
    Write-Host ""
    
    if ($Help) {
        Show-Help
        return
    }
    
    # ARM64 specific notice
    if ($script:SystemInfo.Architecture -eq "ARM64") {
        Write-Warning "Running on ARM64 architecture"
        Write-Info "Docker Desktop supports Windows ARM64 starting from version 4.0+"
        Write-Host ""
    }
    
    # Check for previous incomplete setup
    $lastRepoUrl = Get-State "last_repo_url"
    $lastCloneDir = Get-State "last_clone_dir"
    if ($lastRepoUrl -or $lastCloneDir) {
        Write-Warning "Previous setup was interrupted"
        if ($lastRepoUrl) { Write-Host "Last attempted repository: $lastRepoUrl" -ForegroundColor Yellow }
        if ($lastCloneDir) { Write-Host "Last attempted directory: $lastCloneDir" -ForegroundColor Yellow }
        Write-Host ""
        
        if (-not $Yes) {
            $continueSetup = Read-Host "Continue with previous setup? [Y/n]"
            # Accept empty (default), y, Y, yes, Yes, YES, etc. (case-insensitive yes confirmation)
            if ([string]::IsNullOrEmpty($continueSetup) -or $continueSetup -match '^[Yy]([Ee][Ss])?$') {
                if ($lastRepoUrl) { $RepoUrl = $lastRepoUrl }
                if ($lastCloneDir) { $script:LastCloneDir = $lastCloneDir }
            }
            else {
                Clear-State
            }
        }
        else {
            # Auto-confirm mode, continue with previous
            if ($lastRepoUrl) { $RepoUrl = $lastRepoUrl }
            if ($lastCloneDir) { $script:LastCloneDir = $lastCloneDir }
        }
        Write-Host ""
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
    Write-Host "     - Clone repository to your chosen directory"
    Write-Host ""
    
    Write-Host "  Final Steps:"
    Write-Host "     - Validate installation"
    Write-Host "     - Check system resources"
    Write-Host ""
    
    # Get confirmation unless -Yes is specified
    if (-not $Yes) {
        Write-Host "Do you want to proceed with the installation?" -ForegroundColor Yellow
        $confirmation = Read-Host "Type 'yes' to continue or anything else to exit"

        # Accept y, Y, yes, Yes, YES, etc. (case-insensitive yes confirmation)
        # Pattern: ^[Yy]([Ee][Ss])?$ matches y|Y|yes|Yes|YES|yEs|yeS|YeS|yES|YEs
        if (-not ($confirmation -match '^[Yy]([Ee][Ss])?$')) {
            Write-Warning "Installation cancelled by user"
            exit 0
        }
    }
    else {
        Write-Info "Auto-confirm mode enabled, proceeding with installation..."
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
    Show-Progress "Installing Git"
    Install-Git
    
    Show-Progress "Installing GitHub CLI"
    Install-GitHubCLI
    
    Show-Progress "Installing Docker Desktop"
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
        Write-Host "  3. After restart, run the setup script again from:"
        Write-Host ""
        Write-Host "     https://github.com/Tech-to-Thrive/sm-setup" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "     Copy the Windows command from the Quick Start section" -ForegroundColor White
        Write-Host ""
        Write-Host "  The script will:"
        Write-Host "  - Skip already installed components"
        Write-Host "  - Authenticate with GitHub (if needed)"
        Write-Host "  - Clone your Stack Masters repository"
        Write-Host "  - Complete the environment setup"
        Write-Host ""
        Write-Host "================================================"
        Write-Host ""
        Write-Info "Log file: $LogFile"
        return
    }
    
    # Only proceed with GitHub auth and cloning if no restart is needed
    # Ensure git and gh commands are available (creates wrappers if needed)
    Ensure-CommandAvailable
    
    Show-Progress "Setting up GitHub authentication"
    Authenticate-GitHub
    
    Show-Progress "Cloning repository"
    $cloneDir = Clone-Repository
    
    # Validate installation
    Show-Progress "Validating installation"
    Test-Installation
    
    # Show summary
    Write-Host ""
    Write-Host ""
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
                
                # Change to deploy\scripts directory where the script expects to be run
                $scriptDir = Join-Path $cloneDir "deploy\scripts"
                Push-Location $scriptDir
                try {
                    & .\generate-env-config.ps1
                }
                catch {
                    Write-Error-Custom "Failed to run generate-env-config.ps1: $($_.Exception.Message)"
                    Write-Info "You can run it manually later from: $scriptDir"
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
                Write-Host "  Or manually navigate to: cd `"$cloneDir\deploy\scripts`""
                Write-Host "  And run: .\generate-env-config.ps1"
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

# Cleanup handler for script exit
$script:CleanupDone = $false

function Invoke-Cleanup {
    if ($script:CleanupDone) { return }
    $script:CleanupDone = $true
    
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        Write-Host ""
        Write-Warning "Setup interrupted or failed!"
        
        $currentStep = Get-State "current_step_name"
        if ($currentStep) {
            Write-Host "Failed at step: $currentStep" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "Recovery options:" -ForegroundColor Yellow
        Write-Host "  1. Check the log file for details: $LogFile" -ForegroundColor Cyan
        Write-Host "  2. Fix any issues mentioned above" -ForegroundColor White
        Write-Host "  3. Re-run the script to continue: .\setup-windows.ps1" -ForegroundColor White
        Write-Host ""
        
        # Save current state for recovery
        if ($RepoUrl) {
            Save-State "last_repo_url" $RepoUrl
        }
    }
    elseif ($LASTEXITCODE -eq 0) {
        # Success - clear state
        Clear-State
        Write-Host ""
        Write-Success "Setup completed successfully!"
    }
}

# Register cleanup for Ctrl+C
[console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Invoke-Cleanup
}

# Handle Ctrl+C
trap {
    Write-Host ""
    Write-Warning "Setup interrupted by user"
    Invoke-Cleanup
    exit 130
}

# Run main function
try {
    Main
    Invoke-Cleanup
}
catch {
    Write-Error-Custom "Unexpected error: $($_.Exception.Message)"
    Invoke-Cleanup
    exit 1
}