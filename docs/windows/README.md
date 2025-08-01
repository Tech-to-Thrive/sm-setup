# Windows Server Setup Guide

Complete guide for setting up Stack Masters on Windows Server using PowerShell.

## Prerequisites

- Windows Server 2019, 2022, or 2025
- Administrator privileges
- Internet connectivity
- PowerShell 5.1 or later
- Minimum 4GB RAM, 20GB free disk space

## Quick Installation

### Download and Run
```powershell
# Download the setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"

# Run with default settings
.\setup-windows.ps1
```

### One-Line Installation
```powershell
# Download and execute in one command
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1'))
```

## Command Line Options

### Basic Usage
```powershell
# Interactive setup (default)
.\setup-windows.ps1

# With specific repository
.\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters"

# Skip firewall configuration
.\setup-windows.ps1 -SkipFirewall

# Skip GitHub authentication (for testing)
.\setup-windows.ps1 -SkipAuth

# Show help
.\setup-windows.ps1 -Help
```

### Advanced Examples
```powershell
# Complete automated setup
.\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters-pro" -SkipFirewall

# Testing mode (no auth, no firewall)
.\setup-windows.ps1 -SkipAuth -SkipFirewall
```

## What Gets Installed

### Core Components
1. **Chocolatey** - Package manager for Windows
2. **Git for Windows** - Version control with Unix tools
3. **GitHub CLI** - Repository management and authentication
4. **Docker Desktop** - Container runtime with Docker Compose

### Windows Features Enabled
- **Hyper-V** - Required for Docker Desktop
- **Containers** - Windows container support

### Firewall Configuration
The script configures Windows Firewall with rules for:
- Port 80 (HTTP)
- Port 443 (HTTPS) 
- Port 8080 (Alternative HTTP)

## Installation Process

### Step 1: Prerequisites Check
- Verifies Administrator privileges
- Checks PowerShell execution policy
- Creates log directory

### Step 2: Package Manager Installation
- Installs Chocolatey package manager
- Updates PATH environment variables

### Step 3: Core Tools Installation
- Git for Windows with Unix tools
- GitHub CLI for repository management
- Docker Desktop with Hyper-V support

### Step 4: System Configuration
- Configures Windows Firewall rules
- Enables required Windows features
- Updates environment variables

### Step 5: GitHub Authentication
- Interactive browser-based authentication
- Device code fallback for headless servers
- Repository access validation

### Step 6: Repository Cloning
- Prompts for repository URL
- Validates access permissions
- Clones to `C:\StackMasters\[repo-name]`

### Step 7: Validation
- Tests all installed components
- Checks system resources
- Validates configuration

## Post-Installation

### Next Steps
1. **Restart the system** (required after Docker installation)
2. **Navigate to repository**:
   ```powershell
   cd "C:\StackMasters\[repo-name]"
   ```
3. **Run repository-specific setup** (if available)
4. **Configure Docker Desktop** settings if needed

### Docker Desktop Configuration
After restart, you may need to:
- Accept Docker Desktop license
- Configure resource limits (CPU, Memory)
- Enable Linux containers (if required)

## Troubleshooting

### Common Issues

#### 1. Execution Policy Error
```powershell
# Error: "execution of scripts is disabled on this system"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### 2. Chocolatey Installation Failed
```powershell
# Manual Chocolatey installation
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

#### 3. Docker Desktop Won't Start
- Ensure Hyper-V is enabled: `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`
- Restart the system
- Check BIOS virtualization settings

#### 4. GitHub Authentication Failed
- Use device code flow: https://github.com/login/device
- Check repository access permissions
- Verify GitHub CLI installation: `gh --version`

#### 5. Firewall Rules Not Applied
```powershell
# Manual firewall configuration
New-NetFirewallRule -DisplayName "Stack Masters HTTP 80" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "Stack Masters HTTPS 443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
New-NetFirewallRule -DisplayName "Stack Masters Alt HTTP 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```

### Log Files
- **Installation Log**: `C:\temp\stack-masters-setup.log`
- **Chocolatey Logs**: `C:\ProgramData\chocolatey\logs\`
- **Docker Desktop Logs**: `%APPDATA%\Docker\log\`

### System Requirements Check
```powershell
# Check system resources
Get-WmiObject -Class Win32_ComputerSystem | Select-Object TotalPhysicalMemory
Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object FreeSpace

# Check Windows version
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber

# Check Hyper-V capability
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
```

## Windows Server Versions

### Supported Versions
- **Windows Server 2019** - Full support
- **Windows Server 2022** - Full support  
- **Windows Server 2025** - Full support
- **Windows Server Core** - Limited support (manual configuration required)

### Version-Specific Notes

#### Windows Server 2019
- Requires Windows Updates for Docker Desktop compatibility
- May need manual Hyper-V feature installation

#### Windows Server 2022/2025
- Native Docker Desktop support
- Enhanced container security features
- Better PowerShell integration

#### Windows Server Core
- No GUI for Docker Desktop
- Requires Windows containers only
- Manual configuration of most components

## Security Considerations

### Windows Defender
The script doesn't modify Windows Defender settings. You may need to:
- Add exclusions for Docker directories
- Allow Docker through Windows Defender Firewall
- Configure real-time protection exceptions

### User Account Control (UAC)
- Script must run as Administrator
- UAC prompts may appear during installation
- Consider disabling UAC temporarily for automated deployments

### Network Security
- Only necessary ports are opened (80, 443, 8080)
- SSH not required (uses HTTPS for Git operations)
- GitHub authentication uses OAuth tokens

## Performance Optimization

### Recommended Settings
```powershell
# Set high performance power plan
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# Disable unnecessary services
Set-Service -Name "Themes" -StartupType Disabled
Set-Service -Name "Windows Search" -StartupType Disabled

# Configure Docker Desktop resources
# (Done through Docker Desktop GUI after installation)
```

### Resource Allocation
- **Minimum**: 2 vCPUs, 4GB RAM, 20GB storage
- **Recommended**: 4 vCPUs, 8GB RAM, 40GB storage
- **Docker Desktop**: Allocate 50-75% of available resources

## Integration with Stack Masters

### Directory Structure
```
C:\StackMasters\
├── [repo-name]\           # Cloned repository
│   ├── docker-compose.yml # Stack Masters services
│   ├── .env               # Environment configuration
│   └── scripts\           # Setup and deployment scripts
└── logs\                  # Application logs
```

### Next Steps After Setup
1. **Configure environment variables** in `.env` file
2. **Review Docker Compose services** in `docker-compose.yml`
3. **Run Stack Masters initialization** scripts
4. **Configure DNS/SSL** if deploying publicly

## Automation and CI/CD

### Unattended Installation
```powershell
# Fully automated setup
.\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters" -SkipAuth -SkipFirewall

# With environment variables
$env:REPO_URL = "https://github.com/Tech-to-Thrive/stack-masters"
.\setup-windows.ps1 -SkipAuth
```

### Group Policy Deployment
- Deploy via GPO software installation
- Use startup scripts for domain-joined servers
- Configure Windows Update policies for container hosts

---

For additional support or Windows-specific issues, please open an issue with your Windows version and error details.