# Stack Masters Setup

Universal provisioning scripts for Stack Masters deployment across any Linux/Windows server.

## 🚀 Quick Start

### Linux/Unix Systems
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
```

### Windows Server
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"
.\setup-windows.ps1
```

## 📚 Documentation

For complete documentation, guides, and examples, see the **[docs/](docs/)** directory:

- **[📖 Complete Documentation Index](docs/INDEX.md)** - Start here for full documentation
- **[⚡ Quick Start Guide](docs/setup/QUICK_START.md)** - Get running in minutes
- **[🌐 VPS Provider Guide](docs/providers/PROVIDER_GUIDE.md)** - Provider-specific instructions
- **[🧪 Testing Infrastructure](docs/testing/MULTI_OS_TESTING.md)** - Multi-OS testing suite

## 🌍 Supported Platforms

### VPS Providers
Hostinger, DigitalOcean, Vultr, AWS EC2, Google Cloud, Linode, Hetzner, OVHcloud

### Operating Systems  
Ubuntu, Debian, CentOS, Rocky Linux, AlmaLinux, openSUSE, Arch Linux, Windows Server 2022/2025

### Package Managers
apt, yum/dnf, pacman, zypper, chocolatey

## 🛠️ What Gets Installed

- **Git** - Version control
- **Docker** - Container runtime with Docker Compose  
- **GitHub CLI** - Repository management and authentication
- **System utilities** - curl, wget, build tools
- **Firewall configuration** - Secure port setup (80, 443, 8080)

## 🔧 Advanced Usage

```bash
# Test multiple operating systems
./multi-os-test.sh all

# Keep test instances for inspection
KEEP_INSTANCES=true ./multi-os-test.sh rocky9

# Windows with specific repository
.\setup-windows.ps1 -RepoUrl "https://github.com/Tech-to-Thrive/stack-masters"
```

## 📊 Testing Status

✅ **Tested on 6+ Linux distributions**  
✅ **Windows Server 2022/2025 support**  
✅ **Automated testing infrastructure**  
✅ **Multi-provider validation**

## 🤝 Contributing

- Scripts in root directory
- Documentation in `docs/` directory
- Test results in `test-results/` (git-ignored)
- See `docs/INDEX.md` for complete structure

## 📞 Support

- Open issues in this repository
- Check provider-specific documentation
- Review test logs for troubleshooting

---

**[📖 View Complete Documentation →](docs/INDEX.md)**