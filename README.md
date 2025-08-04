# Stack Masters Setup

One-command installation for Stack Masters. WordPress-simple, enterprise-ready.

## 🎯 **Pick Your Setup:**

### **🚀 Quick Install**

**Linux/Mac:**
```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
```

**Windows:**
```powershell
iwr -useb https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup-windows.ps1 | iex
```

That's it! The script automatically detects your environment:
- ✅ **Servers** - Configures firewall, binds to all interfaces
- ✅ **Desktops** - Skips firewall, localhost only
- ✅ **All systems** - Validates requirements, installs dependencies, launches web wizard

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
Ubuntu, Debian, CentOS, Rocky Linux, AlmaLinux, openSUSE, Arch Linux, Windows Server 2022/2025, Windows 10/11

### Package Managers
apt, yum/dnf, pacman, zypper, winget (Windows Package Manager)

## 🎯 How It Works

1. **Run one command** - Setup script validates your system
2. **Open your browser** - Go to the URL shown (e.g., http://your-ip:58217)
3. **Follow the wizard** - Authenticate GitHub, select repository, configure, deploy
4. **Stack is running** - Everything configured and deployed automatically

## 📋 What Gets Installed

- **Minimal dependencies** - Only what's absolutely needed
- **Pre-validated** - All requirements checked upfront
- **Platform-aware** - Works on Linux, Windows, macOS
- **Zero build time** - Pre-compiled wizard, no npm builds

## 🔧 Advanced Options

```bash
# Force server mode on desktop
./setup.sh --server

# Force local mode on server  
./setup.sh --local

# Windows specific mode
.\setup-windows.ps1 -Mode server
```

## 📊 Testing Status

✅ **Tested on 6+ Linux distributions**  
✅ **Windows Server 2022/2025 support**  
✅ **Automated testing infrastructure**  
✅ **Multi-provider validation**

## 📁 Clean Structure

```
sm-setup/
├── README.md           # You are here
├── setup.sh           # Linux/Mac installer
├── setup-windows.ps1  # Windows installer
├── apps/              # Provisioning wizard
├── docs/              # Documentation
└── scripts/           # Supporting scripts
```

## 📞 Support

- Open issues in this repository
- Check provider-specific documentation
- Review test logs for troubleshooting

---

**[📖 View Complete Documentation →](docs/INDEX.md)**