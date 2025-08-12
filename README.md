# Stack Masters Setup

One-command setup for Stack Masters on any server or local machine.

## Quick Start

Copy and paste ONE command:

### Linux/macOS
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-mac-linux.sh -o setup.sh && chmod +x setup.sh && ./setup.sh
```

### Windows (Run PowerShell as Administrator)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1'))
```

## Community Membership

**Note:** Skool community membership (free or Pro/paid) is required to install this stack:
- **AI Stack Masters (free)** - [AI Stack Masters](https://www.skool.com/ai-stack-masters)
- **AI Stack Master Pros (paid)** - [AI Stack Master Pros](https://www.skool.com/ai-stack-master-pros)

## What This Does

1. **Detects your system** - Works on Ubuntu, Debian, CentOS, Rocky Linux, macOS, Windows Server, Windows 11
2. **Installs requirements** - Git, Docker, GitHub CLI (using winget on Windows, Homebrew on macOS)
3. **Authenticates GitHub** - Secure device code flow
4. **Clones your repository** - You'll select from Skool community repos or provide custom URL
5. **Configures everything** - Automatically runs setup scripts if found

## How It Works

1. **Shows what's already installed** - Checks Git, Docker, GitHub CLI status
2. **Asks for confirmation** - Type 'yes' to proceed with installation
3. **Creates logs** - Saves to `logs/` directory for troubleshooting
4. **Clones your repository** - To `stack-masters/` directory
5. **Runs setup automatically** - If `generate-env-config.sh` is found, runs it

## Troubleshooting

### All Platforms

**"Permission denied" error**
- The script auto-elevates when needed. Never run with sudo upfront.
- Just run the command exactly as shown above.

**"Repository not found" error**
- Ensure you have access to the repository
- The GitHub authentication must complete successfully
- Check if you're authenticated: `gh auth status`

**Docker not starting**
- Linux: `sudo systemctl start docker`
- macOS: Open Docker Desktop from Applications
- Windows: Start Docker Desktop from Start Menu

### Linux

**"No supported package manager found"**
- Ensure apt, yum, dnf, or pacman is installed
- Ubuntu/Debian need apt
- RHEL/CentOS need yum or dnf


### macOS

**"Homebrew not found"**
- Install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

**Docker Desktop required**
- Install from: https://www.docker.com/products/docker-desktop
- Must be running before continuing setup

### Windows

**"Running scripts is disabled"**
- Run PowerShell as Administrator
- Execute: `Set-ExecutionPolicy Bypass -Scope Process -Force`

**"winget not found"** (Windows 10/11)
- Install App Installer from Microsoft Store
- Or download from: https://github.com/microsoft/winget-cli/releases

### Still Having Issues?

1. Check system requirements:
   - 4GB+ RAM (8GB recommended)
   - 20GB+ free disk space
   - Internet connection for downloads

2. Run with options:
   - `--repo-url <URL>` - Specify repository URL upfront
   - `--skip-auth` - Skip GitHub authentication (testing only)
   - `--help` - See all options

3. Get help:
   - Open an issue: https://github.com/Tech-to-Thrive/sm-setup/issues
   - Include your OS version and error messages

## License

See LICENSE.md for details