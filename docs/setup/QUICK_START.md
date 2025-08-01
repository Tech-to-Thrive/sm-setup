# Stack Masters Quick Start

## **Copy-Paste Installation**

### **🖥️ VPS/Server Setup** (Production)
For Hostinger, DigitalOcean, Vultr, AWS, Google Cloud, etc.

**Linux/Unix:**
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash -s -- --server
```

**Windows Server:**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"; .\setup-windows.ps1 -Server
```

### **💻 Local Development** 
For Mac, Windows Desktop, Linux Desktop

**Linux/Mac:**
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash -s -- --local
```

**Windows Desktop:**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"; .\setup-windows.ps1 -Local
```

## What This Does

1. Detects your Linux distribution
2. Installs required dependencies (Git, Docker, GitHub CLI)
3. Configures firewall (opens ports 80, 443, 8080)
4. Sets up GitHub authentication
5. Prompts you for the repository URL to clone
6. Validates your system is ready

## Example URLs Format

When the script prompts for a repository URL, use the full GitHub URL:

- `https://github.com/Tech-to-Thrive/stack-masters`
- `https://github.com/Tech-to-Thrive/stack-masters-pro`
- `https://github.com/Tech-to-Thrive/agent-hosting`

## Requirements

- Fresh Linux VPS (Ubuntu, Debian, RHEL, CentOS, Arch Linux)
- Root access
- 4GB RAM minimum
- 20GB storage minimum
- Internet connection

## Testing Instructions

For the Vultr test server:

1. SSH into the server:
```bash
ssh root@149.28.202.225
```

2. Run the setup script:
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
```

3. When prompted, enter the repository URL you want to test with.

## Troubleshooting

If you encounter issues:

1. Check the log output for specific errors
2. Ensure you have internet connectivity: `ping github.com`
3. Verify you're running as root: `whoami`
4. Check available disk space: `df -h`
5. Check available memory: `free -h`

## Support

For issues, please open an issue in the repository or contact the Tech-to-Thrive team.