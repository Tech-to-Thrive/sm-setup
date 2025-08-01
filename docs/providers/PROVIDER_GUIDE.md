# VPS Provider Quick Setup Guide

This guide provides specific instructions for setting up Stack Masters on popular VPS providers.

## Hostinger VPS

1. **Create VPS Instance:**
   - Log into Hostinger control panel
   - Navigate to VPS section
   - Choose Ubuntu 22.04 as the OS
   - Select at least KVM 2 plan (4GB RAM, 2 vCPUs)
   - Wait for provisioning to complete

2. **Access Your VPS:**
   ```bash
   ssh root@your-vps-ip
   ```

3. **Run Setup Script:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## DigitalOcean

1. **Create Droplet:**
   - Click "Create" → "Droplets"
   - Choose Ubuntu 22.04 LTS
   - Select at least "Basic Regular 4GB" plan
   - Add your SSH key
   - Create Droplet

2. **Configure Firewall:**
   - Go to Networking → Firewalls
   - Create new firewall
   - Add rules for: SSH (22), HTTP (80), HTTPS (443), 8080
   - Apply to your Droplet

3. **Connect and Install:**
   ```bash
   ssh root@droplet-ip
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## AWS EC2

1. **Launch Instance:**
   - Go to EC2 Dashboard
   - Click "Launch Instance"
   - Choose Ubuntu Server 22.04 LTS AMI
   - Select t3.medium or larger
   - Configure Security Group:
     - SSH (22) from your IP
     - HTTP (80) from anywhere
     - HTTPS (443) from anywhere
     - Custom TCP (8080) from anywhere

2. **Connect to Instance:**
   ```bash
   ssh -i your-key.pem ubuntu@ec2-public-ip
   sudo su -
   ```

3. **Run Setup:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## Vultr

1. **Deploy Instance:**
   - Click "Deploy New Instance"
   - Choose "Cloud Compute"
   - Select Ubuntu 22.04 LTS
   - Choose at least 55GB SSD, 2 vCPUs, 4GB RAM
   - Add SSH key (optional but recommended)

2. **Firewall Setup:**
   - Go to Products → Firewall
   - Create firewall group
   - Add rules for ports: 22, 80, 443, 8080
   - Link to your instance

3. **Install Stack Masters:**
   ```bash
   ssh root@vultr-ip
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## Linode

1. **Create Linode:**
   - Click "Create Linode"
   - Choose Ubuntu 22.04 LTS
   - Select Shared CPU → Linode 4GB plan minimum
   - Set root password
   - Create Linode

2. **Configure Firewall:**
   ```bash
   # After connecting via SSH
   ufw allow 22/tcp
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw allow 8080/tcp
   ufw enable
   ```

3. **Run Installation:**
   ```bash
   ssh root@linode-ip
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## Google Cloud Platform

1. **Create VM Instance:**
   - Go to Compute Engine → VM instances
   - Click "Create Instance"
   - Choose Ubuntu 22.04 LTS
   - Select e2-medium or larger
   - Allow HTTP and HTTPS traffic
   - Create

2. **Add Firewall Rules:**
   ```bash
   gcloud compute firewall-rules create stack-masters-ports \
     --allow tcp:80,tcp:443,tcp:8080 \
     --source-ranges 0.0.0.0/0
   ```

3. **Connect and Install:**
   ```bash
   gcloud compute ssh instance-name
   sudo su -
   curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash
   ```

## Common Post-Installation Steps

After the script completes on any provider:

1. **Verify Installation:**
   ```bash
   docker --version
   gh --version
   ```

2. **Check Repository:**
   ```bash
   cd /opt/[your-repo-name]
   ls -la
   ```

3. **Configure DNS:**
   - Point your domain to the VPS IP
   - Set up subdomains for services:
     - `grafana.yourdomain.com`
     - `n8n.yourdomain.com`
     - `stack.yourdomain.com`

4. **SSL Certificates:**
   - The stack includes Nginx Proxy Manager
   - Use Let's Encrypt for free SSL certificates
   - Configure through the NPM interface

## Troubleshooting

### Connection Refused
- Ensure firewall rules are properly configured
- Check if Docker is running: `systemctl status docker`

### GitHub Authentication Failed
- The script will provide a device code
- Visit https://github.com/login/device
- Enter the code to authenticate

### Low Resources Warning
- Upgrade your VPS plan if you see memory/disk warnings
- Minimum recommended: 4GB RAM, 40GB storage

## Support

For provider-specific issues:
- Check provider's documentation
- Contact provider support

For Stack Masters issues:
- Open issue on GitHub repository
- Check logs in `/opt/[repo-name]/logs/`