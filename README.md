# Stack Masters Setup

Universal provisioning scripts for Stack Masters deployment across any Linux/Windows server.

## 🎯 **Pick Your Setup:**

### **🖥️ VPS/Server Deployment** (Production)
*Hostinger, DigitalOcean, AWS, Google Cloud, etc.*

**Linux/Unix:**
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash -s -- --server
```

**Windows Server:**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"; .\setup-windows.ps1 -Server
```

### **💻 Local Development**
*Mac, Windows Desktop, Linux Desktop*

**Linux/Mac:**
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash -s -- --local
```

**Windows Desktop:**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1" -OutFile "setup-windows.ps1"; .\setup-windows.ps1 -Local
```

---

### **What's the Difference?**
- **VPS/Server**: Opens firewall ports, configures security for internet access
- **Local Dev**: Skips firewall, perfect for localhost development

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

## 🎯 **What's the Difference?**

### **VPS/Server Mode** (Default)
- ✅ **Opens firewall ports** for web access and Stack Masters services
- ✅ **Configures security** for internet-facing deployment
- ✅ **Perfect for**: Production, staging, public VPS

### **Local Development Mode**
- ✅ **Skips firewall config** - uses your local system settings
- ✅ **Installs everything** - Git, Docker, GitHub CLI
- ✅ **Perfect for**: Mac, Windows Desktop, Linux Desktop development

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