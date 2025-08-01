# Stack Masters Setup Documentation

Welcome to the comprehensive documentation for Stack Masters setup and deployment across multiple platforms.

## 📋 Table of Contents

### 🚀 Quick Start
- **[Main README](README.md)** - Complete overview and installation guide
- **[Quick Start Guide](setup/QUICK_START.md)** - Get up and running in minutes
- **[Template Usage](setup/TEMPLATE_USAGE.md)** - How to use the CLAUDE.md template

### 🖥️ Platform Support
- **[Provider Guide](providers/PROVIDER_GUIDE.md)** - Step-by-step for major VPS providers
- **[Windows Setup](../setup-windows.ps1)** - PowerShell script for Windows Server

### 🧪 Testing & Validation
- **[Test Results](testing/TEST_RESULTS.md)** - Real-world testing outcomes
- **[Multi-OS Testing](testing/MULTI_OS_TESTING.md)** - Comprehensive testing infrastructure

### 🛠️ Scripts & Tools
- **[Linux Setup Script](../setup.sh)** - Main Linux installation script
- **[Windows Setup Script](../setup-windows.ps1)** - Windows Server setup
- **[Multi-OS Test Suite](../multi-os-test.sh)** - Automated testing infrastructure

## 🎯 Quick Installation

### Linux/Unix Systems
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
```

### Windows Server
```powershell
# Download and run
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"
.\setup-windows.ps1
```

## 🌐 Supported Platforms

### VPS Providers
- Hostinger VPS
- DigitalOcean Droplets
- Vultr Cloud Compute
- AWS EC2
- Google Cloud Compute Engine
- Linode
- Hetzner Cloud
- OVHcloud

### Operating Systems
- **Linux**: Ubuntu, Debian, CentOS, Rocky Linux, AlmaLinux, openSUSE, Arch Linux
- **Windows**: Server 2022, Server 2025 (Standard & Datacenter)

### Package Managers
- `apt` (Ubuntu, Debian)
- `yum`/`dnf` (RHEL, CentOS, Rocky, AlmaLinux)
- `pacman` (Arch Linux)
- `zypper` (SUSE, openSUSE)
- `chocolatey` (Windows)

## 📊 What Gets Installed

### Core Components
- **Git** - Version control
- **Docker** - Container runtime with Docker Compose
- **GitHub CLI** - Repository management and authentication
- **System utilities** - curl, wget, build tools

### Security Configuration
- **Firewall rules** - Opens ports 80, 443, 8080 (HTTP/HTTPS traffic only)
- **SSH access** - Preserves SSH connectivity (port 22)
- **Internal services** - All Stack Masters services accessed via subdomain routing

## 🔧 Advanced Usage

### Environment Variables
```bash
# Keep test instances running for manual inspection
KEEP_INSTANCES=true ./multi-os-test.sh rocky9

# Skip GitHub authentication for testing
./setup.sh --skip-auth
```

### Testing Multiple OS
```bash
# Test all supported operating systems
./multi-os-test.sh all

# Test specific OS
./multi-os-test.sh ubuntu22
./multi-os-test.sh rocky9
./multi-os-test.sh opensuse15
```

### Windows-Specific Options
```powershell
# Skip firewall configuration
.\setup-windows.ps1 -SkipFirewall

# Use specific repository
.\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters-pro"
```

## 🏗️ Architecture Overview

```
Stack Masters Setup Architecture

User Input (Repository URL)
         ↓
OS Detection & Package Manager Selection
         ↓
Core Dependencies Installation
         ↓
GitHub Authentication & Repository Clone
         ↓
Security Configuration (Firewall)
         ↓
System Validation & Health Checks
         ↓
Ready for Stack Masters Deployment
```

## 🔍 Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo ./setup.sh  # Ensure running as root
   ```

2. **GitHub Authentication Failed**
   - Use device code flow: https://github.com/login/device
   - Ensure repository access permissions

3. **Docker Installation Issues**
   - Check system requirements (virtualization support)
   - Verify sufficient disk space (20GB+)

4. **Firewall Configuration Failed**
   - Manually configure required ports: 80, 443, 8080, 22

### Log Files
- **Linux**: Installation logs in `/tmp/stack-masters-setup.log`
- **Windows**: Logs in `C:\temp\stack-masters-setup.log`
- **Testing**: Results in `test-results/[timestamp]/`

## 📈 Monitoring & Validation

The setup script validates:
- ✅ All dependencies installed correctly
- ✅ Docker service running
- ✅ GitHub CLI authenticated
- ✅ Firewall rules configured
- ✅ Sufficient system resources
- ✅ Repository successfully cloned

## 🤝 Contributing

### Documentation Structure
```
docs/
├── INDEX.md              # This file - main documentation index
├── README.md             # Main project README
├── setup/                # Setup and installation guides
│   ├── QUICK_START.md   # Quick start guide
│   └── TEMPLATE_USAGE.md # Template usage instructions
├── providers/            # VPS provider specific guides
│   └── PROVIDER_GUIDE.md # Step-by-step provider instructions
├── testing/             # Testing documentation
│   ├── TEST_RESULTS.md  # Real-world test outcomes
│   └── MULTI_OS_TESTING.md # Testing infrastructure
└── windows/             # Windows-specific documentation
```

### File Organization
- **Scripts**: Root directory (`setup.sh`, `setup-windows.ps1`, etc.)
- **Documentation**: `docs/` directory with categorized subdirectories  
- **Test Results**: `test-results/` directory (git-ignored)
- **Sensitive Files**: Listed in `.gitignore`

## 📞 Support

For issues or questions:
- **General Issues**: Open issue in GitHub repository
- **Provider-Specific**: Check provider documentation first
- **Windows Issues**: Ensure PowerShell execution policy allows scripts
- **Testing Issues**: Review test logs in `test-results/` directory

## 📄 License

This setup infrastructure is released under the MIT License.

---

**Last Updated**: 2025-08-01  
**Version**: 1.0.0  
**Tested Platforms**: 6+ Linux distributions, Windows Server 2022/2025