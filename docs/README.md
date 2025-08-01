# Stack Masters Setup Script

A universal provisioning script that prepares fresh Linux VPS/servers for Stack Masters deployment across any hosting provider.

## Overview

This setup script automates the entire process of preparing a bare metal Linux server for Stack Masters deployment, including:

- OS detection and package manager configuration
- Core dependency installation (Git, Docker, GitHub CLI)
- Firewall configuration for required ports
- GitHub authentication with browser-based flow
- Automatic repository detection (Community vs Pro edition)
- System validation and health checks

## Supported Hosting Providers

This script works with any Linux VPS from:
- **Hostinger** - VPS and Cloud hosting
- **DigitalOcean** - Droplets
- **Vultr** - Cloud Compute instances
- **AWS** - EC2 instances
- **Linode** - Shared or Dedicated CPU instances
- **Google Cloud** - Compute Engine VMs
- **Azure** - Virtual Machines
- **Hetzner** - Cloud servers
- **OVHcloud** - VPS instances
- Any other VPS provider running Linux

## Supported Operating Systems

- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12
- RHEL 8, 9
- CentOS 8 Stream
- AlmaLinux 8, 9
- Rocky Linux 8, 9
- Arch Linux (latest)
- Any Linux distribution with apt, yum, dnf, or pacman package managers

## Prerequisites

- Fresh Linux VPS instance
- Root access (the script must be run as root)
- Internet connectivity
- Minimum specifications:
  - 2 vCPUs (4 recommended)
  - 4GB RAM (8GB recommended)
  - 20GB storage (40GB recommended)
  - Public IP address

## Quick Start

### One-Line Installation

For users who want to get started immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | sudo bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | sudo bash
```

### Provider-Specific Notes

**Hostinger VPS:**
- Use their VPS control panel to deploy Ubuntu 22.04
- Enable SSH access from the control panel
- Run the setup script via SSH

**DigitalOcean:**
- Create a Droplet with Ubuntu 22.04
- Use SSH keys for authentication
- Run the script after first login

**AWS EC2:**
- Launch an Ubuntu AMI
- Configure security group for ports 80, 443, 8080, 22
- Use EC2 Instance Connect or SSH key

### Manual Installation

1. Download the script:
```bash
curl -O https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh
chmod +x setup.sh
```

2. Run as root:
```bash
sudo ./setup.sh
```

## What the Script Does

### 1. System Detection
- Identifies the Linux distribution and version
- Selects the appropriate package manager (apt/yum/dnf)
- Updates system packages

### 2. Core Dependencies
Installs essential packages:
- curl, wget, ca-certificates
- gnupg, lsb-release
- software-properties-common
- Distribution-specific utilities

### 3. Software Installation
- **Git**: Latest version from system repositories
- **GitHub CLI**: Latest version from official GitHub repository
- **Docker**: Latest CE version with docker-compose plugin
- **Docker BuildX**: For multi-platform builds

### 4. Firewall Configuration
Opens only the necessary external ports:
- 80/tcp (HTTP - Nginx reverse proxy)
- 443/tcp (HTTPS - Nginx reverse proxy)
- 8080/tcp (Alternative HTTP port)
- 22/tcp (SSH - preserved for remote access)

All internal services (Grafana, Stack Manager, n8n, Prometheus, etc.) are accessed through Nginx subdomain routing and are not directly exposed to the internet.

Supports both UFW (Ubuntu/Debian) and firewalld (RHEL/CentOS).

### 5. GitHub Authentication
- Initiates GitHub CLI authentication
- Supports browser-based authentication (opens browser if available)
- Falls back to device code authentication for headless servers
- Users paste the device code at: https://github.com/login/device

### 6. Repository Cloning
The script prompts you to enter the GitHub repository URL you want to clone. This allows flexibility for testing different repositories:
- Enter the full GitHub URL (e.g., `https://github.com/Tech-to-Thrive/stack-masters`)
- The script validates your access to the repository
- Clones to `/opt/[repository-name]`

### 7. System Validation
Performs final checks:
- Docker functionality test
- Disk space verification (warns if <20GB)
- Memory verification (warns if <4GB)

## Post-Installation Steps

After the script completes successfully:

1. Navigate to the cloned repository:
```bash
cd /opt/[repository-name]  # e.g., /opt/stack-masters or /opt/agent-hosting
```

2. Configure your environment (if available):
```bash
./setup-environment.sh  # Check if this script exists in your repository
```

3. Start the stack:
```bash
./install.sh  # Or follow repository-specific instructions
```

## Troubleshooting

### Permission Denied
Ensure you're running the script as root:
```bash
sudo ./setup.sh
```

### GitHub Authentication Issues
If browser authentication fails:
1. The script will automatically fall back to device code authentication
2. Copy the provided code
3. Visit https://github.com/login/device
4. Enter the code

### Firewall Configuration
If the script can't detect your firewall:
- Manually configure your firewall to allow the required ports
- Check the script output for the list of ports

### Docker Installation Failed
Try manually installing Docker:
```bash
# For Ubuntu/Debian
curl -fsSL https://get.docker.com | sudo bash

# For RHEL/CentOS
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io
```

## Security Considerations

- The script requires root access to install system packages
- GitHub authentication tokens are stored securely by the GitHub CLI
- Only external-facing ports (80, 443, 8080) are opened in the firewall
- All internal services remain protected behind Nginx reverse proxy
- No credentials or sensitive data are stored by the script

## Support

For issues or questions:
- Open an issue in the respective GitHub repository
- Contact the Tech-to-Thrive team for support

## License

This setup script is released under the MIT License.