#!/usr/bin/env node

/**
 * Digital Ocean End-to-End Deployment Script
 * Actually provisions the full agent-hosting stack on a DO droplet
 */

const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const fs = require('fs').promises;
const path = require('path');
const readline = require('readline');
const crypto = require('crypto');

// Configuration
const CONFIG = {
  // Digital Ocean defaults
  dropletName: 'agent-hosting-prod',
  region: 'nyc3',
  size: 's-2vcpu-4gb', // 4GB RAM as requested
  image: 'docker-20-04', // Ubuntu 20.04 with Docker pre-installed
  tags: ['agent-hosting', 'production'],
  
  // Repository
  repoUrl: 'https://github.com/Tech-to-Thrive/agent-hosting.git',
  branch: 'feature/provisioning-production-ready',
  
  // Local paths
  projectRoot: path.join(__dirname, '..'),
  sshKeyPath: process.env.HOME + '/.ssh/id_rsa'
};

class DigitalOceanDeployer {
  constructor() {
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
    this.dropletInfo = null;
    this.startTime = Date.now();
  }

  async prompt(question) {
    return new Promise(resolve => {
      this.rl.question(question, resolve);
    });
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const colors = {
      info: '\x1b[36m',
      success: '\x1b[32m',
      warning: '\x1b[33m',
      error: '\x1b[31m'
    };
    console.log(`${colors[level]}[${timestamp}] ${message}\x1b[0m`);
  }

  async checkPrerequisites() {
    this.log('Checking prerequisites...');
    
    // Check for doctl
    try {
      await execAsync('which doctl');
    } catch (error) {
      throw new Error('doctl CLI not found. Install it from: https://docs.digitalocean.com/reference/doctl/how-to/install/');
    }
    
    // Check for SSH key
    try {
      await fs.access(CONFIG.sshKeyPath);
    } catch (error) {
      throw new Error(`SSH key not found at ${CONFIG.sshKeyPath}. Generate one with: ssh-keygen -t rsa`);
    }
    
    // Check if authenticated
    try {
      await execAsync('doctl auth whoami');
      this.log('✓ Digital Ocean CLI authenticated', 'success');
    } catch (error) {
      throw new Error('Not authenticated with Digital Ocean. Run: doctl auth init');
    }
  }

  async getCloudflareConfig() {
    this.log('Checking for Cloudflare configuration...');
    
    const envPath = path.join(CONFIG.projectRoot, '.env');
    try {
      const envContent = await fs.readFile(envPath, 'utf8');
      const cfToken = envContent.match(/CLOUDFLARE_API_TOKEN=(.+)/)?.[1];
      const cfAccountId = envContent.match(/CLOUDFLARE_ACCOUNT_ID=(.+)/)?.[1];
      const domain = envContent.match(/DOMAIN_NAME=(.+)/)?.[1];
      
      if (cfToken && cfAccountId && domain) {
        this.log('✓ Cloudflare configuration found', 'success');
        return { cfToken, cfAccountId, domain };
      }
    } catch (error) {
      // No .env file
    }
    
    this.log('No Cloudflare configuration found in .env', 'warning');
    const useCf = await this.prompt('Configure Cloudflare DNS? (y/N): ');
    
    if (useCf.toLowerCase() === 'y') {
      const cfToken = await this.prompt('Cloudflare API Token: ');
      const cfAccountId = await this.prompt('Cloudflare Account ID: ');
      const domain = await this.prompt('Domain name (e.g., example.com): ');
      return { cfToken, cfAccountId, domain };
    }
    
    return null;
  }

  async createDroplet() {
    this.log('Creating Digital Ocean droplet...');
    
    // Get SSH key fingerprint
    const { stdout: keys } = await execAsync('doctl compute ssh-key list --format ID,Name,FingerPrint --no-header');
    const sshKeyId = keys.split('\n')[0]?.split(/\s+/)[0];
    
    if (!sshKeyId) {
      throw new Error('No SSH keys found. Add your key: doctl compute ssh-key import');
    }
    
    // Create droplet
    const createCmd = `doctl compute droplet create ${CONFIG.dropletName} \
      --region ${CONFIG.region} \
      --size ${CONFIG.size} \
      --image ${CONFIG.image} \
      --ssh-keys ${sshKeyId} \
      --tag-names ${CONFIG.tags.join(',')} \
      --wait \
      --format ID,PublicIPv4,Status \
      --no-header`;
    
    this.log('Creating droplet (this may take 2-3 minutes)...');
    const { stdout } = await execAsync(createCmd);
    
    const [id, ip, status] = stdout.trim().split(/\s+/);
    this.dropletInfo = { id, ip, status };
    
    this.log(`✓ Droplet created: ${ip}`, 'success');
    
    // Wait for SSH to be ready
    await this.waitForSSH(ip);
    
    return this.dropletInfo;
  }

  async waitForSSH(ip) {
    this.log('Waiting for SSH to be ready...');
    
    for (let i = 0; i < 30; i++) {
      try {
        await execAsync(`ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${ip} 'echo "SSH ready"'`);
        this.log('✓ SSH connection established', 'success');
        return;
      } catch (error) {
        process.stdout.write('.');
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
    
    throw new Error('SSH connection timeout');
  }

  async prepareDroplet(ip) {
    this.log('Preparing droplet environment...');
    
    // Update system and install dependencies
    const commands = [
      'apt-get update',
      'apt-get install -y git curl wget jq unzip',
      'curl -fsSL https://get.docker.com | sh',
      'systemctl enable docker',
      'systemctl start docker',
      'curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose',
      'chmod +x /usr/local/bin/docker-compose',
      'docker --version',
      'docker-compose --version'
    ];
    
    for (const cmd of commands) {
      this.log(`Running: ${cmd}`);
      try {
        await execAsync(`ssh root@${ip} '${cmd}'`);
      } catch (error) {
        this.log(`Warning: ${error.message}`, 'warning');
      }
    }
    
    this.log('✓ Droplet prepared', 'success');
  }

  async deployStack(ip, cloudflareConfig) {
    this.log('Deploying agent-hosting stack...');
    
    // Clone repository
    this.log('Cloning repository...');
    await execAsync(`ssh root@${ip} 'git clone ${CONFIG.repoUrl} /root/agent-hosting'`);
    await execAsync(`ssh root@${ip} 'cd /root/agent-hosting && git checkout ${CONFIG.branch}'`);
    
    // Copy local .env if exists
    const localEnvPath = path.join(CONFIG.projectRoot, '.env');
    try {
      await fs.access(localEnvPath);
      this.log('Copying local .env configuration...');
      await execAsync(`scp ${localEnvPath} root@${ip}:/root/agent-hosting/.env`);
    } catch (error) {
      this.log('No local .env found, using defaults', 'warning');
    }
    
    // Generate secure configuration
    this.log('Generating secure configuration...');
    const configScript = `cd /root/agent-hosting && cat > .env.production << 'EOF'
# Auto-generated production configuration
COMPOSE_PROJECT_NAME=agent-hosting-prod
DOMAIN=${cloudflareConfig?.domain || ip}
TZ=UTC

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${this.generatePassword()}
POSTGRES_DB=n8n
POSTGRES_HOST=db-postgres
POSTGRES_PORT=5432

# Redis
REDIS_HOST=cache-redis
REDIS_PORT=6379
REDIS_PASSWORD=${this.generatePassword()}

# Security Keys
JWT_SECRET=${crypto.randomBytes(32).toString('base64')}
ANON_KEY=${crypto.randomBytes(32).toString('base64')}
SERVICE_ROLE_KEY=${crypto.randomBytes(32).toString('base64')}
VAULT_ENC_KEY=${this.generatePassword(32)}
STACK_MANAGER_ENCRYPTION_KEY=${crypto.randomBytes(32).toString('hex')}
WEBHOOK_SECRET=${crypto.randomBytes(32).toString('hex')}

# Admin
MASTER_ADMIN_EMAIL=admin@${cloudflareConfig?.domain || 'agent-hosting.local'}
MASTER_ADMIN_PASSWORD=${this.generatePassword()}

# Services
N8N_HOST=0.0.0.0
N8N_PORT=5678
STACK_MANAGER_UI_PORT=3001
STACK_MANAGER_API_PORT=3002
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090

# Cloudflare (if configured)
${cloudflareConfig ? `CLOUDFLARE_API_TOKEN=${cloudflareConfig.cfToken}
CLOUDFLARE_ACCOUNT_ID=${cloudflareConfig.cfAccountId}
CLOUDFLARE_ZONE_ID=${cloudflareConfig.cfZoneId || ''}` : '# No Cloudflare configuration'}

EOF`;
    
    await execAsync(`ssh root@${ip} '${configScript}'`);
    
    // Merge configurations
    await execAsync(`ssh root@${ip} 'cd /root/agent-hosting && cp .env .env.backup 2>/dev/null || true'`);
    await execAsync(`ssh root@${ip} 'cd /root/agent-hosting && cat .env.production >> .env'`);
    
    // Run the provisioning script
    this.log('Running provisioning script...');
    
    // Stream the provisioning output
    const provisionProcess = exec(`ssh root@${ip} 'cd /root/agent-hosting && bash provision.sh'`);
    
    provisionProcess.stdout.on('data', (data) => {
      process.stdout.write(data);
    });
    
    provisionProcess.stderr.on('data', (data) => {
      process.stderr.write(data);
    });
    
    await new Promise((resolve, reject) => {
      provisionProcess.on('exit', (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new Error(`Provisioning failed with code ${code}`));
        }
      });
    });
    
    this.log('✓ Stack deployed successfully', 'success');
  }

  async configureFirewall(ip) {
    this.log('Configuring firewall rules...');
    
    const ports = [
      '22/tcp',    // SSH
      '80/tcp',    // HTTP
      '443/tcp',   // HTTPS
      '3000/tcp',  // Grafana
      '3001/tcp',  // Stack Manager UI
      '3002/tcp',  // Stack Manager API
      '5678/tcp',  // n8n
      '9090/tcp'   // Prometheus
    ];
    
    for (const port of ports) {
      await execAsync(`ssh root@${ip} 'ufw allow ${port}'`);
    }
    
    await execAsync(`ssh root@${ip} 'ufw --force enable'`);
    this.log('✓ Firewall configured', 'success');
  }

  async configureCloudflare(ip, cloudflareConfig) {
    if (!cloudflareConfig) return;
    
    this.log('Configuring Cloudflare DNS...');
    
    const { cfToken, cfAccountId, domain } = cloudflareConfig;
    
    // Get zone ID
    const zoneCmd = `curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" \
      -H "Authorization: Bearer ${cfToken}" \
      -H "Content-Type: application/json"`;
    
    const { stdout: zoneResponse } = await execAsync(zoneCmd);
    const zoneData = JSON.parse(zoneResponse);
    const zoneId = zoneData.result[0]?.id;
    
    if (!zoneId) {
      throw new Error(`Zone not found for domain: ${domain}`);
    }
    
    // Create A record
    const recordCmd = `curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records" \
      -H "Authorization: Bearer ${cfToken}" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"agent","content":"${ip}","ttl":120,"proxied":true}'`;
    
    await execAsync(recordCmd);
    
    // Create wildcard CNAME
    const wildcardCmd = `curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records" \
      -H "Authorization: Bearer ${cfToken}" \
      -H "Content-Type: application/json" \
      --data '{"type":"CNAME","name":"*.agent","content":"agent.${domain}","ttl":120,"proxied":true}'`;
    
    await execAsync(wildcardCmd);
    
    this.log(`✓ DNS configured: agent.${domain} → ${ip}`, 'success');
  }

  async verifyDeployment(ip, cloudflareConfig) {
    this.log('Verifying deployment...');
    
    const baseUrl = cloudflareConfig ? `https://agent.${cloudflareConfig.domain}` : `http://${ip}`;
    
    const services = [
      { name: 'n8n', url: `${baseUrl}:5678`, expected: [200, 302] },
      { name: 'Stack Manager UI', url: `${baseUrl}:3001`, expected: [200] },
      { name: 'Stack Manager API', url: `${baseUrl}:3002/api/health`, expected: [200] },
      { name: 'Grafana', url: `${baseUrl}:3000`, expected: [200, 302] },
      { name: 'Prometheus', url: `${baseUrl}:9090`, expected: [200] }
    ];
    
    this.log('\nService Status:');
    for (const service of services) {
      try {
        const { stdout } = await execAsync(`curl -s -o /dev/null -w "%{http_code}" ${service.url} || echo "000"`);
        const statusCode = parseInt(stdout.trim());
        
        if (service.expected.includes(statusCode)) {
          this.log(`✓ ${service.name}: ${service.url} (${statusCode})`, 'success');
        } else {
          this.log(`✗ ${service.name}: ${service.url} (${statusCode})`, 'error');
        }
      } catch (error) {
        this.log(`✗ ${service.name}: Connection failed`, 'error');
      }
    }
    
    // Get container status
    this.log('\nDocker Container Status:');
    const { stdout: containers } = await execAsync(`ssh root@${ip} 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'`);
    console.log(containers);
  }

  generatePassword(length = 16) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
    let password = '';
    for (let i = 0; i < length; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return password;
  }

  async displaySummary(ip, cloudflareConfig) {
    const elapsed = Math.round((Date.now() - this.startTime) / 1000);
    const domain = cloudflareConfig?.domain;
    
    console.log('\n' + '='.repeat(60));
    console.log('🎉 DEPLOYMENT SUCCESSFUL!');
    console.log('='.repeat(60));
    console.log(`\nDeployment Time: ${elapsed} seconds`);
    console.log(`Droplet IP: ${ip}`);
    
    if (domain) {
      console.log(`\nAccess your services at:`);
      console.log(`  n8n:             https://agent.${domain}:5678`);
      console.log(`  Stack Manager:   https://agent.${domain}:3001`);
      console.log(`  Grafana:         https://agent.${domain}:3000`);
      console.log(`  Prometheus:      https://agent.${domain}:9090`);
    } else {
      console.log(`\nAccess your services at:`);
      console.log(`  n8n:             http://${ip}:5678`);
      console.log(`  Stack Manager:   http://${ip}:3001`);
      console.log(`  Grafana:         http://${ip}:3000`);
      console.log(`  Prometheus:      http://${ip}:9090`);
    }
    
    console.log('\nSSH Access:');
    console.log(`  ssh root@${ip}`);
    
    console.log('\nNext Steps:');
    console.log('  1. Access Stack Manager and complete setup');
    console.log('  2. Configure storage providers for backups');
    console.log('  3. Import Grafana dashboards');
    console.log('  4. Set up monitoring alerts');
    
    console.log('\nUseful Commands:');
    console.log(`  View logs:     ssh root@${ip} 'cd /root/agent-hosting && docker compose logs -f'`);
    console.log(`  Stop stack:    ssh root@${ip} 'cd /root/agent-hosting && docker compose down'`);
    console.log(`  Destroy:       doctl compute droplet delete ${CONFIG.dropletName} --force`);
    
    console.log('\n' + '='.repeat(60));
  }

  async cleanup() {
    this.rl.close();
  }

  async run() {
    try {
      // Prerequisites
      await this.checkPrerequisites();
      
      // Get configuration
      const cloudflareConfig = await this.getCloudflareConfig();
      
      // Confirm deployment
      console.log('\n' + '='.repeat(60));
      console.log('DEPLOYMENT CONFIGURATION:');
      console.log(`  Droplet: ${CONFIG.dropletName}`);
      console.log(`  Region: ${CONFIG.region}`);
      console.log(`  Size: ${CONFIG.size} (4GB RAM)`);
      console.log(`  Image: ${CONFIG.image}`);
      if (cloudflareConfig) {
        console.log(`  Domain: agent.${cloudflareConfig.domain}`);
      }
      console.log('='.repeat(60) + '\n');
      
      const confirm = await this.prompt('Continue with deployment? (y/N): ');
      if (confirm.toLowerCase() !== 'y') {
        this.log('Deployment cancelled', 'warning');
        return;
      }
      
      // Create droplet
      const { ip } = await this.createDroplet();
      
      // Prepare environment
      await this.prepareDroplet(ip);
      
      // Deploy stack
      await this.deployStack(ip, cloudflareConfig);
      
      // Configure firewall
      await this.configureFirewall(ip);
      
      // Configure DNS
      await this.configureCloudflare(ip, cloudflareConfig);
      
      // Wait for services to stabilize
      this.log('Waiting for services to start (30 seconds)...');
      await new Promise(resolve => setTimeout(resolve, 30000));
      
      // Verify deployment
      await this.verifyDeployment(ip, cloudflareConfig);
      
      // Display summary
      await this.displaySummary(ip, cloudflareConfig);
      
    } catch (error) {
      this.log(`Deployment failed: ${error.message}`, 'error');
      
      if (this.dropletInfo) {
        const cleanup = await this.prompt('\nDelete the droplet? (y/N): ');
        if (cleanup.toLowerCase() === 'y') {
          await execAsync(`doctl compute droplet delete ${this.dropletInfo.id} --force`);
          this.log('Droplet deleted', 'success');
        }
      }
      
      process.exit(1);
    } finally {
      await this.cleanup();
    }
  }
}

// Run the deployment
const deployer = new DigitalOceanDeployer();
deployer.run().catch(console.error);