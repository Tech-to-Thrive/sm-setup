#!/usr/bin/env node

const express = require('express');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);

const app = express();
const PORT = process.env.PORT || 8080;

// Create HTTP server for WebSocket support
const server = require('http').createServer(app);

// Simple WebSocket implementation (no external dependencies)
const WebSocket = require('ws');
const wss = new WebSocket.Server({ server });

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Storage for deployment states
const deploymentStates = new Map();
const activeSockets = new Map();

// Deployment state persistence
const STATE_FILE = path.join(__dirname, '.provision-state.json');

// Load persisted states on startup
const loadDeploymentStates = async () => {
  try {
    const fileExists = await fs.access(STATE_FILE).then(() => true).catch(() => false);
    if (fileExists) {
      const data = await fs.readFile(STATE_FILE, 'utf8');
      const states = JSON.parse(data);
      Object.entries(states).forEach(([id, state]) => {
        deploymentStates.set(id, state);
      });
      console.log(`Loaded ${deploymentStates.size} deployment states`);
    }
  } catch (error) {
    console.error('Failed to load deployment states:', error);
  }
};

// Save deployment states
const saveDeploymentStates = async () => {
  try {
    const states = Object.fromEntries(deploymentStates);
    await fs.writeFile(STATE_FILE, JSON.stringify(states, null, 2));
  } catch (error) {
    console.error('Failed to save deployment states:', error);
  }
};

// Deployment steps with detailed configuration
const DEPLOYMENT_STEPS = [
  { 
    id: 'validate', 
    name: 'Validating Environment', 
    description: 'Checking system requirements and dependencies',
    icon: '✓',
    retryable: true
  },
  { 
    id: 'backup', 
    name: 'Creating Backup', 
    description: 'Backing up existing configuration',
    icon: '💾',
    retryable: true
  },
  { 
    id: 'docker', 
    name: 'Docker Setup', 
    description: 'Verifying Docker installation and configuration',
    icon: '🐳',
    critical: true
  },
  { 
    id: 'network', 
    name: 'Network Configuration', 
    description: 'Creating isolated Docker networks',
    icon: '🌐',
    retryable: true
  },
  { 
    id: 'volumes', 
    name: 'Storage Setup', 
    description: 'Creating persistent storage volumes',
    icon: '💿',
    retryable: true
  },
  { 
    id: 'images', 
    name: 'Downloading Images', 
    description: 'Pulling required Docker images',
    icon: '📦',
    retryable: true,
    longRunning: true
  },
  { 
    id: 'database', 
    name: 'Database Services', 
    description: 'Starting PostgreSQL and Redis',
    icon: '🗄️',
    critical: true
  },
  { 
    id: 'proxy', 
    name: 'Proxy Services', 
    description: 'Starting MITM proxy for certificate management',
    icon: '🔐'
  },
  { 
    id: 'core', 
    name: 'Core Applications', 
    description: 'Starting n8n and Stack Manager',
    icon: '🚀',
    critical: true
  },
  { 
    id: 'monitoring', 
    name: 'Monitoring Stack', 
    description: 'Starting Prometheus, Grafana, and Loki',
    icon: '📊'
  },
  { 
    id: 'health', 
    name: 'Health Checks', 
    description: 'Verifying all services are responsive',
    icon: '🏥',
    retryable: true
  },
  { 
    id: 'ssl', 
    name: 'SSL Configuration', 
    description: 'Setting up SSL certificates and DNS',
    icon: '🔒',
    optional: true
  },
  { 
    id: 'finalize', 
    name: 'Finalizing', 
    description: 'Saving deployment state and cleaning up',
    icon: '🎉'
  }
];

// Command definitions for each step
const STEP_COMMANDS = {
  validate: [
    { cmd: 'node --version', description: 'Node.js version check' },
    { cmd: 'docker --version', description: 'Docker version check' },
    { cmd: 'test -w . || exit 1', description: 'Write permissions check' }
  ],
  backup: [
    { cmd: 'mkdir -p backups', description: 'Creating backup directory' },
    { cmd: 'test -f .env && cp .env backups/.env.$(date +%s) || true', description: 'Backing up environment' }
  ],
  docker: [
    { cmd: 'docker info', description: 'Docker daemon check' },
    { cmd: 'docker compose version', description: 'Docker Compose check' }
  ],
  network: [
    { cmd: 'docker network create agent-hosting-net 2>/dev/null || true', description: 'Creating main network' },
    { cmd: 'docker network create agent-hosting-internal 2>/dev/null || true', description: 'Creating internal network' }
  ],
  volumes: [
    { cmd: 'docker volume create agent-postgres-data', description: 'PostgreSQL data volume' },
    { cmd: 'docker volume create agent-redis-data', description: 'Redis data volume' },
    { cmd: 'docker volume create agent-n8n-data', description: 'n8n data volume' },
    { cmd: 'docker volume create agent-certs', description: 'Certificates volume' }
  ],
  images: [
    { cmd: 'docker pull postgres:17', description: 'PostgreSQL image', progress: true },
    { cmd: 'docker pull redis:alpine', description: 'Redis image', progress: true },
    { cmd: 'docker pull n8nio/n8n:latest', description: 'n8n image', progress: true },
    { cmd: 'docker pull grafana/grafana:latest', description: 'Grafana image', progress: true }
  ],
  database: [
    { cmd: 'docker compose up -d db-postgres', description: 'Starting PostgreSQL' },
    { cmd: 'sleep 5', description: 'Waiting for database' },
    { cmd: 'docker compose up -d cache-redis', description: 'Starting Redis' }
  ],
  proxy: [
    { cmd: 'docker compose up -d proxy-mitm', description: 'Starting MITM proxy' },
    { cmd: 'sleep 3', description: 'Waiting for proxy initialization' }
  ],
  core: [
    { cmd: 'docker compose up -d app-n8n', description: 'Starting n8n' },
    { cmd: 'docker compose up -d app-stackmanager-api', description: 'Starting Stack Manager API' },
    { cmd: 'docker compose up -d app-stackmanager-scheduler', description: 'Starting Stack Manager Scheduler' }
  ],
  monitoring: [
    { cmd: 'docker compose up -d metrics-prometheus', description: 'Starting Prometheus' },
    { cmd: 'docker compose up -d ui-grafana', description: 'Starting Grafana' },
    { cmd: 'docker compose up -d logs-loki', description: 'Starting Loki' }
  ],
  health: [
    { cmd: 'curl -f http://localhost:5678/healthz || exit 1', description: 'n8n health check' },
    { cmd: 'curl -f http://localhost:3002/api/health || exit 1', description: 'Stack Manager health check' },
    { cmd: 'curl -f http://localhost:3080 || exit 1', description: 'Grafana health check' }
  ],
  ssl: [], // Dynamic based on provider
  finalize: [
    { cmd: 'echo "Deployment completed successfully!"', description: 'Success message' }
  ]
};

// Deployment executor class
class DeploymentExecutor {
  constructor(deploymentId, config) {
    this.deploymentId = deploymentId;
    this.config = config;
    this.state = {
      id: deploymentId,
      status: 'pending',
      currentStep: -1,
      steps: DEPLOYMENT_STEPS.map(step => ({
        ...step,
        status: 'pending',
        logs: [],
        error: null,
        progress: 0,
        startTime: null,
        endTime: null,
        duration: null
      })),
      startTime: new Date().toISOString(),
      endTime: null,
      config: this.sanitizeConfig(config)
    };
  }

  sanitizeConfig(config) {
    // Remove sensitive data from stored config
    const sanitized = { ...config };
    ['password', 'token', 'secret', 'key'].forEach(key => {
      Object.keys(sanitized).forEach(configKey => {
        if (configKey.toLowerCase().includes(key)) {
          sanitized[configKey] = '***';
        }
      });
    });
    return sanitized;
  }

  async execute() {
    this.updateState({ status: 'running' });

    for (let i = 0; i < this.state.steps.length; i++) {
      const step = this.state.steps[i];

      // Skip completed steps (for resume functionality)
      if (step.status === 'completed') {
        this.log(i, 'Step already completed, skipping...', 'info');
        continue;
      }

      // Skip optional steps if not enabled
      if (step.optional && !this.shouldRunOptionalStep(step.id)) {
        this.updateStep(i, { status: 'skipped' });
        continue;
      }

      this.state.currentStep = i;
      this.updateState({});

      try {
        await this.executeStep(i);
      } catch (error) {
        if (step.critical) {
          this.updateState({ status: 'failed' });
          return;
        }
        // Non-critical failures allow continuation
        this.log(i, `Non-critical step failed: ${error.message}`, 'warning');
      }
    }

    if (this.state.status === 'running') {
      this.updateState({
        status: 'completed',
        endTime: new Date().toISOString()
      });
    }
  }

  shouldRunOptionalStep(stepId) {
    if (stepId === 'ssl') {
      return this.config.sslProvider && this.config.sslProvider !== 'none';
    }
    return true;
  }

  async executeStep(stepIndex) {
    const step = this.state.steps[stepIndex];
    
    this.updateStep(stepIndex, {
      status: 'running',
      startTime: new Date().toISOString(),
      progress: 0
    });

    try {
      let commands = STEP_COMMANDS[step.id] || [];
      
      // Handle dynamic SSL commands based on provider
      if (step.id === 'ssl') {
        commands = this.getSSLCommands();
      }
      
      const totalCommands = commands.length;

      for (let i = 0; i < commands.length; i++) {
        const command = commands[i];
        this.log(stepIndex, command.description, 'info');

        try {
          if (command.progress) {
            // For long-running commands, simulate progress
            await this.executeWithProgress(stepIndex, command, (i / totalCommands) * 100);
          } else {
            const { stdout, stderr } = await execAsync(command.cmd, {
              cwd: path.dirname(__dirname)
            });

            if (stdout) this.log(stepIndex, stdout.trim(), 'output');
            if (stderr && !command.ignoreStderr) this.log(stepIndex, stderr.trim(), 'warning');
          }

          this.updateStep(stepIndex, {
            progress: ((i + 1) / totalCommands) * 100
          });
        } catch (error) {
          throw this.enhanceError(step.id, error);
        }
      }

      const duration = new Date() - new Date(step.startTime);
      this.updateStep(stepIndex, {
        status: 'completed',
        endTime: new Date().toISOString(),
        duration,
        progress: 100
      });

    } catch (error) {
      this.updateStep(stepIndex, {
        status: 'failed',
        error: {
          message: error.message,
          code: error.code,
          troubleshooting: this.getTroubleshooting(step.id, error),
          canRetry: step.retryable
        },
        endTime: new Date().toISOString()
      });
      throw error;
    }
  }

  async executeWithProgress(stepIndex, command, baseProgress) {
    // Simulate progress for long-running commands
    const progressInterval = setInterval(() => {
      const currentProgress = this.state.steps[stepIndex].progress;
      if (currentProgress < baseProgress + 90) {
        this.updateStep(stepIndex, {
          progress: Math.min(currentProgress + 10, baseProgress + 90)
        });
      }
    }, 1000);

    try {
      const { stdout, stderr } = await execAsync(command.cmd, {
        cwd: path.dirname(__dirname)
      });
      
      clearInterval(progressInterval);
      
      if (stdout) this.log(stepIndex, stdout.trim(), 'output');
      if (stderr) this.log(stepIndex, stderr.trim(), 'warning');
    } catch (error) {
      clearInterval(progressInterval);
      throw error;
    }
  }

  getSSLCommands() {
    const { sslProvider, domain, subdomain, cloudflareToken, cloudflareAccountId, tunnelName } = this.config;
    
    switch (sslProvider) {
      case 'cloudflare-tunnel':
        return [
          { 
            cmd: 'docker pull cloudflare/cloudflared:latest', 
            description: 'Pulling Cloudflare tunnel image',
            progress: true 
          },
          {
            cmd: `echo "Creating Cloudflare tunnel configuration..."`,
            description: 'Configuring tunnel'
          },
          {
            cmd: `docker run --rm -v $(pwd)/configs/cloudflare:/root/.cloudflared cloudflare/cloudflared:latest tunnel login`,
            description: 'Authenticating with Cloudflare'
          },
          {
            cmd: `docker run --rm -v $(pwd)/configs/cloudflare:/root/.cloudflared cloudflare/cloudflared:latest tunnel create ${tunnelName || 'agent-hosting'}`,
            description: 'Creating tunnel'
          },
          {
            cmd: `docker run --rm -v $(pwd)/configs/cloudflare:/root/.cloudflared cloudflare/cloudflared:latest tunnel route dns ${tunnelName || 'agent-hosting'} ${subdomain}.${domain}`,
            description: 'Creating DNS route'
          },
          {
            cmd: 'docker compose --profile cloudflare-tunnel up -d',
            description: 'Starting Cloudflare tunnel service'
          }
        ];
        
      case 'cloudflare-api':
        return [
          {
            cmd: `echo "Configuring Cloudflare DNS via API..."`,
            description: 'Setting up Cloudflare DNS'
          },
          {
            cmd: `curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflareAccountId}/dns_records" \\
                  -H "Authorization: Bearer ${cloudflareToken}" \\
                  -H "Content-Type: application/json" \\
                  --data '{"type":"A","name":"${subdomain}","content":"${this.getServerIP()}","ttl":120,"proxied":true}'`,
            description: 'Creating DNS A record'
          },
          {
            cmd: `curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflareAccountId}/dns_records" \\
                  -H "Authorization: Bearer ${cloudflareToken}" \\
                  -H "Content-Type: application/json" \\
                  --data '{"type":"CNAME","name":"*.${subdomain}","content":"${subdomain}.${domain}","ttl":120,"proxied":true}'`,
            description: 'Creating wildcard CNAME'
          }
        ];
        
      case 'nginx-proxy':
        return [
          {
            cmd: 'docker compose --profile ssl-dns up -d npm-app npm-db',
            description: 'Starting Nginx Proxy Manager'
          },
          {
            cmd: 'sleep 10',
            description: 'Waiting for NPM to initialize'
          },
          {
            cmd: `echo "Nginx Proxy Manager started. Access at http://localhost:81"`,
            description: 'NPM ready for configuration'
          },
          {
            cmd: `echo "Default login: admin@example.com / changeme"`,
            description: 'NPM credentials info'
          }
        ];
        
      default:
        return [];
    }
  }
  
  getServerIP() {
    // In production, this would detect the actual server IP
    // For now, return a placeholder that user must update
    return 'YOUR_SERVER_IP';
  }

  enhanceError(stepId, error) {
    const enhanced = new Error(error.message);
    enhanced.code = error.code;
    enhanced.stepId = stepId;
    return enhanced;
  }

  getTroubleshooting(stepId, error) {
    const troubleshooting = {
      docker: {
        title: 'Docker Installation Required',
        description: 'Docker is not installed or not running',
        solutions: [
          'Install Docker Desktop from https://docker.com',
          'Ensure Docker daemon is running',
          'On Linux, add user to docker group: sudo usermod -aG docker $USER'
        ],
        documentationUrl: 'https://docs.docker.com/get-docker/',
        aiDiagnostic: true
      },
      network: {
        title: 'Network Configuration Issue',
        description: 'Failed to create Docker networks',
        solutions: [
          'Check if networks already exist: docker network ls',
          'Remove existing networks: docker network rm agent-hosting-net',
          'Ensure Docker daemon has network permissions'
        ],
        documentationUrl: 'https://docs.docker.com/network/',
        aiDiagnostic: true
      },
      database: {
        title: 'Database Startup Failed',
        description: 'PostgreSQL or Redis failed to start',
        solutions: [
          'Check if ports 5432 or 6379 are in use',
          'View logs: docker compose logs db-postgres',
          'Ensure sufficient disk space and memory'
        ],
        documentationUrl: 'https://github.com/Tech-to-Thrive/agent-hosting/wiki/database-troubleshooting',
        aiDiagnostic: true
      },
      health: {
        title: 'Service Health Check Failed',
        description: 'One or more services are not responding',
        solutions: [
          'Wait a few moments for services to fully start',
          'Check service logs: docker compose logs',
          'Verify all required ports are available'
        ],
        documentationUrl: 'https://github.com/Tech-to-Thrive/agent-hosting/wiki/health-checks',
        aiDiagnostic: false
      }
    };

    // Port conflict detection
    if (error.message.includes('port is already allocated')) {
      const port = error.message.match(/bind.*?:(\d+)/)?.[1];
      return {
        title: 'Port Conflict Detected',
        description: `Port ${port} is already in use by another application`,
        solutions: [
          `Find process using port: lsof -ti:${port}`,
          `Stop the process: kill $(lsof -ti:${port})`,
          `Or change the port in your .env file`
        ],
        documentationUrl: 'https://github.com/Tech-to-Thrive/agent-hosting/wiki/port-conflicts',
        aiDiagnostic: true,
        quickFix: `kill $(lsof -ti:${port} 2>/dev/null) || true`
      };
    }

    return troubleshooting[stepId] || {
      title: 'Deployment Step Failed',
      description: error.message,
      solutions: [
        'Check the error message above',
        'Review the step logs for details',
        'Consult the documentation'
      ],
      documentationUrl: 'https://github.com/Tech-to-Thrive/agent-hosting/wiki/troubleshooting',
      aiDiagnostic: true
    };
  }

  log(stepIndex, message, level = 'info') {
    const logEntry = {
      timestamp: new Date().toISOString(),
      message,
      level
    };

    this.state.steps[stepIndex].logs.push(logEntry);
    this.broadcast('log', { stepIndex, logEntry });
  }

  updateStep(stepIndex, updates) {
    Object.assign(this.state.steps[stepIndex], updates);
    this.updateState({});
  }

  updateState(updates) {
    Object.assign(this.state, updates);
    deploymentStates.set(this.deploymentId, this.state);
    saveDeploymentStates();
    this.broadcast('state', this.state);
  }

  broadcast(type, data) {
    const message = JSON.stringify({ type, data, deploymentId: this.deploymentId });
    
    activeSockets.forEach((ws, clientId) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      }
    });
  }
}

// WebSocket connection handling
wss.on('connection', (ws) => {
  const clientId = crypto.randomBytes(16).toString('hex');
  activeSockets.set(clientId, ws);
  
  console.log(`Client connected: ${clientId}`);

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      
      if (data.type === 'subscribe' && data.deploymentId) {
        // Send current state if exists
        const state = deploymentStates.get(data.deploymentId);
        if (state) {
          ws.send(JSON.stringify({
            type: 'state',
            data: state,
            deploymentId: data.deploymentId
          }));
        }
      }
    } catch (error) {
      console.error('WebSocket message error:', error);
    }
  });

  ws.on('close', () => {
    activeSockets.delete(clientId);
    console.log(`Client disconnected: ${clientId}`);
  });
});

// API Routes
app.get('/api/deployments/:id', (req, res) => {
  const state = deploymentStates.get(req.params.id);
  if (state) {
    res.json(state);
  } else {
    res.status(404).json({ error: 'Deployment not found' });
  }
});

app.post('/api/deployments/:id/retry/:stepIndex', async (req, res) => {
  const { id, stepIndex } = req.params;
  const state = deploymentStates.get(id);
  
  if (!state) {
    return res.status(404).json({ error: 'Deployment not found' });
  }

  const step = state.steps[parseInt(stepIndex)];
  if (!step || !step.error?.canRetry) {
    return res.status(400).json({ error: 'Step cannot be retried' });
  }

  // Reset step status
  step.status = 'pending';
  step.error = null;
  step.logs = [];
  
  // Resume deployment from this step
  const executor = new DeploymentExecutor(id, state.config);
  executor.state = state;
  executor.state.status = 'running';
  executor.state.currentStep = parseInt(stepIndex);
  
  // Execute in background
  executor.execute().catch(console.error);
  
  res.json({ message: 'Retry initiated' });
});

app.post('/api/deployments/:id/diagnose/:stepIndex', async (req, res) => {
  const { id, stepIndex } = req.params;
  const state = deploymentStates.get(id);
  
  if (!state) {
    return res.status(404).json({ error: 'Deployment not found' });
  }

  const step = state.steps[parseInt(stepIndex)];
  if (!step || !step.error) {
    return res.status(400).json({ error: 'No error to diagnose' });
  }

  // AI-powered diagnostic (mock implementation)
  const diagnosis = {
    problem: step.error.message,
    analysis: `The ${step.name} step failed due to: ${step.error.message}`,
    recommendations: [
      {
        action: 'Check Docker installation',
        command: 'docker --version && docker ps',
        explanation: 'Ensures Docker is installed and running'
      },
      {
        action: 'Review system resources',
        command: 'df -h && free -m',
        explanation: 'Checks disk space and memory availability'
      },
      {
        action: 'Inspect service logs',
        command: `docker compose logs ${step.id}`,
        explanation: 'Shows detailed logs for the failed service'
      }
    ],
    confidenceScore: 0.85
  };

  res.json(diagnosis);
});

app.post('/api/deploy', async (req, res) => {
  const deploymentId = crypto.randomBytes(16).toString('hex');
  const config = req.body;

  // Create and start deployment
  const executor = new DeploymentExecutor(deploymentId, config);
  deploymentStates.set(deploymentId, executor.state);
  
  // Execute deployment in background
  executor.execute().catch(error => {
    console.error('Deployment failed:', error);
  });

  res.json({ 
    deploymentId, 
    websocketUrl: `ws://localhost:${PORT}`,
    message: 'Deployment started'
  });
});

// Generate configuration
app.post('/api/generate-config', (req, res) => {
  const {
    adminEmail,
    adminPassword,
    domain,
    subdomain,
    sslProvider,
    cloudflareToken,
    cloudflareAccountId,
    tunnelName,
    postgresPassword,
    redisPassword
  } = req.body;

  const jwtSecret = crypto.randomBytes(32).toString('hex');
  const encryptionKey = crypto.randomBytes(32).toString('hex');

  const config = `# Agent Hosting Configuration
# Generated: ${new Date().toISOString()}

# Admin Credentials
MASTER_ADMIN_EMAIL=${adminEmail}
MASTER_ADMIN_PASSWORD=${adminPassword}
MASTER_FIRST_NAME=Admin
MASTER_LAST_NAME=User

# Domain Configuration
DOMAIN=${domain || 'localhost'}
SUBDOMAIN=${subdomain || 'agent'}
SSL_PROVIDER=${sslProvider || 'none'}

# Cloudflare Configuration (if applicable)
${sslProvider === 'cloudflare-tunnel' || sslProvider === 'cloudflare-api' ? `CLOUDFLARE_API_TOKEN=${cloudflareToken || ''}
CLOUDFLARE_ACCOUNT_ID=${cloudflareAccountId || ''}
${sslProvider === 'cloudflare-tunnel' ? `CLOUDFLARE_TUNNEL_NAME=${tunnelName || 'agent-hosting'}` : ''}` : '# No Cloudflare configuration needed'}

# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${postgresPassword || crypto.randomBytes(16).toString('hex')}
POSTGRES_DB=agent_hosting

# Redis Configuration  
REDIS_PASSWORD=${redisPassword || crypto.randomBytes(16).toString('hex')}

# Security Keys
JWT_SECRET=${jwtSecret}
ENCRYPTION_KEY=${encryptionKey}
SUPABASE_ANON_KEY=${crypto.randomBytes(32).toString('hex')}
SUPABASE_SERVICE_KEY=${crypto.randomBytes(32).toString('hex')}

# Service URLs
N8N_URL=http://app-n8n:5678
STACK_MANAGER_API_URL=http://app-stackmanager-api:3002
GRAFANA_URL=http://ui-grafana:3080

# Port Configuration
N8N_PORT=5678
STACK_MANAGER_UI_PORT=3001
STACK_MANAGER_API_PORT=3002
GRAFANA_PORT=3080
PROMETHEUS_PORT=9090
`;

  res.json({ 
    config,
    deploymentReady: true
  });
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    activeDeployments: deploymentStates.size,
    activeSockets: activeSockets.size
  });
});

// Serve the UI
app.get('/', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agent Hosting - Advanced Provisioning</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0a0a0a;
      color: #fff;
      line-height: 1.6;
      overflow-x: hidden;
    }
    
    .container {
      max-width: 1400px;
      margin: 0 auto;
      padding: 20px;
    }
    
    header {
      background: #111;
      border-bottom: 1px solid #333;
      padding: 20px 0;
      margin-bottom: 30px;
    }
    
    .header-content {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    h1 {
      font-size: 28px;
      font-weight: 600;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    
    .status-badge {
      padding: 8px 16px;
      background: #1a1a1a;
      border: 1px solid #333;
      border-radius: 20px;
      font-size: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    
    .status-indicator {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #10b981;
      animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
      0% { opacity: 1; }
      50% { opacity: 0.5; }
      100% { opacity: 1; }
    }
    
    .deployment-container {
      display: grid;
      grid-template-columns: 350px 1fr;
      gap: 30px;
      height: calc(100vh - 200px);
    }
    
    .steps-sidebar {
      background: #111;
      border: 1px solid #333;
      border-radius: 12px;
      padding: 20px;
      overflow-y: auto;
    }
    
    .step-item {
      display: flex;
      align-items: center;
      padding: 12px;
      margin-bottom: 8px;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s;
      position: relative;
    }
    
    .step-item:hover {
      background: #1a1a1a;
    }
    
    .step-item.active {
      background: #1a1a1a;
      border: 1px solid #667eea;
    }
    
    .step-item.running {
      animation: breathing 2s ease-in-out infinite;
    }
    
    @keyframes breathing {
      0% { background: #1a1a1a; }
      50% { background: #252525; }
      100% { background: #1a1a1a; }
    }
    
    .step-icon {
      width: 40px;
      height: 40px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 20px;
      margin-right: 12px;
      background: #1a1a1a;
      border: 1px solid #333;
    }
    
    .step-item.completed .step-icon {
      background: #10b981;
      border-color: #10b981;
    }
    
    .step-item.failed .step-icon {
      background: #ef4444;
      border-color: #ef4444;
    }
    
    .step-item.running .step-icon {
      background: #3b82f6;
      border-color: #3b82f6;
    }
    
    .step-info {
      flex: 1;
    }
    
    .step-name {
      font-weight: 500;
      margin-bottom: 2px;
    }
    
    .step-description {
      font-size: 12px;
      color: #888;
    }
    
    .step-status {
      position: absolute;
      top: 8px;
      right: 8px;
      font-size: 11px;
      padding: 2px 8px;
      border-radius: 4px;
      background: #1a1a1a;
      border: 1px solid #333;
    }
    
    .step-progress {
      position: absolute;
      bottom: 0;
      left: 0;
      height: 2px;
      background: #3b82f6;
      border-radius: 0 0 8px 8px;
      transition: width 0.3s ease;
    }
    
    .logs-container {
      background: #111;
      border: 1px solid #333;
      border-radius: 12px;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    
    .logs-header {
      padding: 20px;
      border-bottom: 1px solid #333;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .logs-content {
      flex: 1;
      padding: 20px;
      overflow-y: auto;
      font-family: 'Monaco', 'Consolas', monospace;
      font-size: 13px;
      line-height: 1.5;
    }
    
    .log-entry {
      margin-bottom: 8px;
      display: flex;
      align-items: flex-start;
    }
    
    .log-timestamp {
      color: #666;
      margin-right: 12px;
      flex-shrink: 0;
    }
    
    .log-message {
      flex: 1;
      word-break: break-word;
    }
    
    .log-entry.info .log-message { color: #3b82f6; }
    .log-entry.success .log-message { color: #10b981; }
    .log-entry.warning .log-message { color: #f59e0b; }
    .log-entry.error .log-message { color: #ef4444; }
    .log-entry.output { 
      background: #1a1a1a;
      padding: 8px;
      margin: 4px 0;
      border-radius: 4px;
      font-size: 12px;
    }
    
    .error-panel {
      background: #1f1315;
      border: 1px solid #ef4444;
      border-radius: 8px;
      padding: 20px;
      margin-top: 20px;
    }
    
    .error-title {
      color: #ef4444;
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 12px;
    }
    
    .error-description {
      color: #fbbf24;
      margin-bottom: 16px;
    }
    
    .solutions {
      background: #1a1a1a;
      border-radius: 4px;
      padding: 12px;
      margin-bottom: 16px;
    }
    
    .solution-item {
      display: flex;
      align-items: flex-start;
      margin-bottom: 8px;
    }
    
    .solution-item::before {
      content: '•';
      color: #3b82f6;
      margin-right: 8px;
    }
    
    .action-buttons {
      display: flex;
      gap: 12px;
      margin-top: 20px;
    }
    
    .btn {
      padding: 10px 20px;
      border: none;
      border-radius: 6px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 500;
      transition: all 0.2s;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }
    
    .btn-primary {
      background: #667eea;
      color: white;
    }
    
    .btn-primary:hover {
      background: #5a67d8;
    }
    
    .btn-secondary {
      background: #374151;
      color: white;
    }
    
    .btn-secondary:hover {
      background: #4b5563;
    }
    
    .btn-danger {
      background: #ef4444;
      color: white;
    }
    
    .btn-danger:hover {
      background: #dc2626;
    }
    
    .config-form {
      background: #111;
      border: 1px solid #333;
      border-radius: 12px;
      padding: 40px;
      max-width: 600px;
      margin: 0 auto;
    }
    
    .form-group {
      margin-bottom: 24px;
    }
    
    .form-label {
      display: block;
      margin-bottom: 8px;
      font-weight: 500;
      font-size: 14px;
      color: #e5e7eb;
    }
    
    .form-input {
      width: 100%;
      padding: 12px;
      background: #1a1a1a;
      border: 1px solid #333;
      border-radius: 6px;
      color: white;
      font-size: 14px;
      transition: border-color 0.2s;
    }
    
    .form-input:focus {
      outline: none;
      border-color: #667eea;
    }
    
    .ssl-options {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 12px;
      margin-top: 12px;
    }
    
    .ssl-option {
      background: #1a1a1a;
      border: 2px solid #333;
      border-radius: 8px;
      padding: 16px;
      cursor: pointer;
      transition: all 0.2s;
    }
    
    .ssl-option:hover {
      border-color: #667eea;
    }
    
    .ssl-option.selected {
      border-color: #667eea;
      background: #1e1b4b;
    }
    
    .ssl-option-title {
      font-weight: 500;
      margin-bottom: 4px;
    }
    
    .ssl-option-desc {
      font-size: 12px;
      color: #888;
    }
    
    .conditional-fields {
      margin-top: 16px;
      padding: 16px;
      background: #1a1a1a;
      border-radius: 6px;
      border: 1px solid #333;
    }
    
    .form-hint {
      font-size: 12px;
      color: #888;
      margin-top: 4px;
    }
    
    .deployment-stats {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 20px;
      margin-bottom: 30px;
    }
    
    .stat-card {
      background: #111;
      border: 1px solid #333;
      border-radius: 8px;
      padding: 20px;
      text-align: center;
    }
    
    .stat-value {
      font-size: 32px;
      font-weight: 600;
      margin-bottom: 4px;
    }
    
    .stat-label {
      font-size: 14px;
      color: #888;
    }
    
    .loading-spinner {
      display: inline-block;
      width: 16px;
      height: 16px;
      border: 2px solid #333;
      border-top-color: #667eea;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    
    .hidden { display: none; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="header-content">
        <h1>Agent Hosting Provisioning</h1>
        <div class="status-badge">
          <span class="status-indicator"></span>
          <span>System Ready</span>
        </div>
      </div>
    </header>

    <!-- Configuration Form -->
    <div id="configView" class="config-form">
      <h2 style="margin-bottom: 30px;">Configure Your Deployment</h2>
      
      <form id="configForm">
        <div class="form-group">
          <label class="form-label">Admin Email</label>
          <input type="email" name="adminEmail" class="form-input" required>
          <div class="form-hint">Primary administrator email address</div>
        </div>
        
        <div class="form-group">
          <label class="form-label">Admin Password</label>
          <input type="password" name="adminPassword" class="form-input" required>
          <div class="form-hint">Strong password for admin access</div>
        </div>
        
        <div class="form-group">
          <label class="form-label">Domain</label>
          <input type="text" name="domain" class="form-input" placeholder="example.com">
          <div class="form-hint">Your domain name (required for SSL)</div>
        </div>
        
        <div class="form-group">
          <label class="form-label">Subdomain</label>
          <input type="text" name="subdomain" class="form-input" placeholder="agent" value="agent">
          <div class="form-hint">Subdomain prefix for your services</div>
        </div>
        
        <div class="form-group">
          <label class="form-label">SSL/DNS Configuration</label>
          <div class="ssl-options">
            <div class="ssl-option" onclick="selectSSLOption('cloudflare-tunnel')" data-option="cloudflare-tunnel">
              <div class="ssl-option-title">🚇 Cloudflare Tunnel</div>
              <div class="ssl-option-desc">Zero exposed ports, most secure</div>
            </div>
            <div class="ssl-option" onclick="selectSSLOption('cloudflare-api')" data-option="cloudflare-api">
              <div class="ssl-option-title">☁️ Cloudflare API</div>
              <div class="ssl-option-desc">Proxy with API management</div>
            </div>
            <div class="ssl-option" onclick="selectSSLOption('nginx-proxy')" data-option="nginx-proxy">
              <div class="ssl-option-title">🔒 Nginx Proxy Manager</div>
              <div class="ssl-option-desc">Self-managed SSL certificates</div>
            </div>
            <div class="ssl-option selected" onclick="selectSSLOption('none')" data-option="none">
              <div class="ssl-option-title">🔓 No SSL</div>
              <div class="ssl-option-desc">Development only</div>
            </div>
          </div>
          <input type="hidden" name="sslProvider" value="none">
        </div>
        
        <!-- Cloudflare-specific fields -->
        <div id="cloudflareFields" class="conditional-fields hidden">
          <div class="form-group">
            <label class="form-label">Cloudflare API Token</label>
            <input type="password" name="cloudflareToken" class="form-input">
            <div class="form-hint">API token with DNS edit permissions</div>
          </div>
          
          <div class="form-group">
            <label class="form-label">Cloudflare Account ID</label>
            <input type="text" name="cloudflareAccountId" class="form-input">
            <div class="form-hint">Found in your Cloudflare dashboard</div>
          </div>
          
          <div id="tunnelFields" class="hidden">
            <div class="form-group">
              <label class="form-label">Tunnel Name</label>
              <input type="text" name="tunnelName" class="form-input" placeholder="agent-hosting">
              <div class="form-hint">Name for your Cloudflare tunnel</div>
            </div>
          </div>
        </div>
        
        <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 20px;">
          Start Deployment
        </button>
      </form>
    </div>

    <!-- Deployment View -->
    <div id="deploymentView" class="hidden">
      <div class="deployment-stats">
        <div class="stat-card">
          <div class="stat-value" id="totalSteps">0</div>
          <div class="stat-label">Total Steps</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" id="completedSteps">0</div>
          <div class="stat-label">Completed</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" id="deploymentTime">00:00</div>
          <div class="stat-label">Elapsed Time</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" id="deploymentStatus">-</div>
          <div class="stat-label">Status</div>
        </div>
      </div>

      <div class="deployment-container">
        <div class="steps-sidebar" id="stepsList">
          <!-- Steps will be rendered here -->
        </div>
        
        <div class="logs-container">
          <div class="logs-header">
            <h3 id="currentStepName">Deployment Logs</h3>
            <div class="action-buttons">
              <button class="btn btn-secondary" onclick="downloadLogs()">
                📥 Download Logs
              </button>
              <button class="btn btn-secondary" onclick="clearLogs()">
                🗑️ Clear
              </button>
            </div>
          </div>
          <div class="logs-content" id="logsContent">
            <!-- Logs will be rendered here -->
          </div>
        </div>
      </div>
    </div>
  </div>

  <script>
    let currentDeploymentId = null;
    let ws = null;
    let deploymentState = null;
    let startTime = null;

    // Check for existing deployment on page load
    const urlParams = new URLSearchParams(window.location.search);
    const resumeId = urlParams.get('deployment');
    
    if (resumeId) {
      resumeDeployment(resumeId);
    }

    // SSL option selection
    function selectSSLOption(option) {
      // Update visual selection
      document.querySelectorAll('.ssl-option').forEach(el => {
        el.classList.remove('selected');
      });
      document.querySelector(\`[data-option="\${option}"]\`).classList.add('selected');
      
      // Update hidden input
      document.querySelector('input[name="sslProvider"]').value = option;
      
      // Show/hide conditional fields
      const cloudflareFields = document.getElementById('cloudflareFields');
      const tunnelFields = document.getElementById('tunnelFields');
      
      if (option === 'cloudflare-tunnel' || option === 'cloudflare-api') {
        cloudflareFields.classList.remove('hidden');
        
        // Make Cloudflare fields required
        cloudflareFields.querySelectorAll('input').forEach(input => {
          input.required = true;
        });
        
        if (option === 'cloudflare-tunnel') {
          tunnelFields.classList.remove('hidden');
        } else {
          tunnelFields.classList.add('hidden');
        }
      } else {
        cloudflareFields.classList.add('hidden');
        
        // Remove required from Cloudflare fields
        cloudflareFields.querySelectorAll('input').forEach(input => {
          input.required = false;
        });
      }
    }

    // Configuration form submission
    document.getElementById('configForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      
      const formData = new FormData(e.target);
      const config = Object.fromEntries(formData);
      
      try {
        const response = await fetch('/api/deploy', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(config)
        });
        
        const data = await response.json();
        startDeployment(data.deploymentId);
      } catch (error) {
        alert('Failed to start deployment: ' + error.message);
      }
    });

    function startDeployment(deploymentId) {
      currentDeploymentId = deploymentId;
      startTime = new Date();
      
      // Update URL for resume capability
      window.history.pushState({}, '', \`?deployment=\${deploymentId}\`);
      
      // Switch views
      document.getElementById('configView').classList.add('hidden');
      document.getElementById('deploymentView').classList.remove('hidden');
      
      // Connect WebSocket
      connectWebSocket();
      
      // Start elapsed time counter
      setInterval(updateElapsedTime, 1000);
    }

    async function resumeDeployment(deploymentId) {
      try {
        const response = await fetch(\`/api/deployments/\${deploymentId}\`);
        if (response.ok) {
          const state = await response.json();
          currentDeploymentId = deploymentId;
          deploymentState = state;
          
          // Switch to deployment view
          document.getElementById('configView').classList.add('hidden');
          document.getElementById('deploymentView').classList.remove('hidden');
          
          // Render current state
          renderDeploymentState(state);
          
          // Connect WebSocket for updates
          connectWebSocket();
          
          // Start elapsed time if still running
          if (state.status === 'running') {
            startTime = new Date(state.startTime);
            setInterval(updateElapsedTime, 1000);
          }
        }
      } catch (error) {
        console.error('Failed to resume deployment:', error);
      }
    }

    function connectWebSocket() {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      ws = new WebSocket(\`\${protocol}//\${window.location.host}\`);
      
      ws.onopen = () => {
        console.log('WebSocket connected');
        ws.send(JSON.stringify({ 
          type: 'subscribe', 
          deploymentId: currentDeploymentId 
        }));
      };
      
      ws.onmessage = (event) => {
        const message = JSON.parse(event.data);
        
        if (message.type === 'state') {
          deploymentState = message.data;
          renderDeploymentState(message.data);
        } else if (message.type === 'log') {
          appendLog(message.data.stepIndex, message.data.logEntry);
        }
      };
      
      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
      };
      
      ws.onclose = () => {
        console.log('WebSocket disconnected');
        // Attempt reconnection after 2 seconds
        setTimeout(connectWebSocket, 2000);
      };
    }

    function renderDeploymentState(state) {
      // Update stats
      document.getElementById('totalSteps').textContent = state.steps.length;
      document.getElementById('completedSteps').textContent = 
        state.steps.filter(s => s.status === 'completed').length;
      document.getElementById('deploymentStatus').textContent = 
        state.status.charAt(0).toUpperCase() + state.status.slice(1);
      
      // Render steps
      const stepsList = document.getElementById('stepsList');
      stepsList.innerHTML = state.steps.map((step, index) => \`
        <div class="step-item \${step.status} \${index === state.currentStep ? 'active' : ''}" 
             onclick="selectStep(\${index})">
          <div class="step-icon">\${step.icon}</div>
          <div class="step-info">
            <div class="step-name">\${step.name}</div>
            <div class="step-description">\${step.description}</div>
          </div>
          <div class="step-status">\${step.status}</div>
          \${step.progress ? \`<div class="step-progress" style="width: \${step.progress}%"></div>\` : ''}
        </div>
      \`).join('');
      
      // Show current step logs
      if (state.currentStep >= 0) {
        selectStep(state.currentStep);
      }
      
      // Show error panel if failed
      if (state.status === 'failed') {
        const failedStep = state.steps.find(s => s.status === 'failed');
        if (failedStep && failedStep.error) {
          showErrorPanel(failedStep, state.steps.indexOf(failedStep));
        }
      }
    }

    function selectStep(stepIndex) {
      if (!deploymentState) return;
      
      const step = deploymentState.steps[stepIndex];
      document.getElementById('currentStepName').textContent = step.name;
      
      // Clear and show logs for selected step
      const logsContent = document.getElementById('logsContent');
      logsContent.innerHTML = '';
      
      step.logs.forEach(log => {
        appendLog(stepIndex, log, false);
      });
      
      // Show error panel if step failed
      if (step.status === 'failed' && step.error) {
        showErrorPanel(step, stepIndex);
      }
      
      // Update active step styling
      document.querySelectorAll('.step-item').forEach((el, i) => {
        el.classList.toggle('active', i === stepIndex);
      });
    }

    function appendLog(stepIndex, logEntry, autoScroll = true) {
      const logsContent = document.getElementById('logsContent');
      
      const logDiv = document.createElement('div');
      logDiv.className = \`log-entry \${logEntry.level}\`;
      
      const timestamp = new Date(logEntry.timestamp).toLocaleTimeString();
      logDiv.innerHTML = \`
        <span class="log-timestamp">\${timestamp}</span>
        <span class="log-message">\${escapeHtml(logEntry.message)}</span>
      \`;
      
      logsContent.appendChild(logDiv);
      
      if (autoScroll) {
        logsContent.scrollTop = logsContent.scrollHeight;
      }
    }

    function showErrorPanel(step, stepIndex) {
      const logsContent = document.getElementById('logsContent');
      
      const errorPanel = document.createElement('div');
      errorPanel.className = 'error-panel';
      errorPanel.innerHTML = \`
        <div class="error-title">\${step.error.troubleshooting.title}</div>
        <div class="error-description">\${step.error.troubleshooting.description}</div>
        
        <div class="solutions">
          <strong>Suggested Solutions:</strong>
          \${step.error.troubleshooting.solutions.map(s => \`
            <div class="solution-item">\${s}</div>
          \`).join('')}
        </div>
        
        <div class="action-buttons">
          \${step.error.canRetry ? \`
            <button class="btn btn-primary" onclick="retryStep(\${stepIndex})">
              🔄 Retry Step
            </button>
          \` : ''}
          
          \${step.error.troubleshooting.aiDiagnostic ? \`
            <button class="btn btn-secondary" onclick="runDiagnostics(\${stepIndex})">
              🤖 AI Diagnostics
            </button>
          \` : ''}
          
          <a href="\${step.error.troubleshooting.documentationUrl}" 
             target="_blank" 
             class="btn btn-secondary">
            📚 Documentation
          </a>
        </div>
      \`;
      
      logsContent.appendChild(errorPanel);
    }

    async function retryStep(stepIndex) {
      try {
        const response = await fetch(\`/api/deployments/\${currentDeploymentId}/retry/\${stepIndex}\`, {
          method: 'POST'
        });
        
        if (response.ok) {
          console.log('Retry initiated');
        }
      } catch (error) {
        alert('Failed to retry step: ' + error.message);
      }
    }

    async function runDiagnostics(stepIndex) {
      try {
        const response = await fetch(\`/api/deployments/\${currentDeploymentId}/diagnose/\${stepIndex}\`, {
          method: 'POST'
        });
        
        const diagnosis = await response.json();
        
        // Show diagnosis in modal or panel
        alert('AI Diagnosis:\\n\\n' + 
              diagnosis.analysis + '\\n\\n' +
              'Recommendations:\\n' + 
              diagnosis.recommendations.map(r => '• ' + r.action).join('\\n'));
      } catch (error) {
        alert('Failed to run diagnostics: ' + error.message);
      }
    }

    function updateElapsedTime() {
      if (!startTime || deploymentState?.status === 'completed' || deploymentState?.status === 'failed') {
        return;
      }
      
      const elapsed = Math.floor((new Date() - startTime) / 1000);
      const minutes = Math.floor(elapsed / 60);
      const seconds = elapsed % 60;
      
      document.getElementById('deploymentTime').textContent = 
        \`\${minutes.toString().padStart(2, '0')}:\${seconds.toString().padStart(2, '0')}\`;
    }

    function downloadLogs() {
      if (!deploymentState) return;
      
      const logs = deploymentState.steps.flatMap(step => 
        step.logs.map(log => \`[\${new Date(log.timestamp).toISOString()}] [\${step.name}] [\${log.level}] \${log.message}\`)
      ).join('\\n');
      
      const blob = new Blob([logs], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = \`deployment-\${currentDeploymentId}-logs.txt\`;
      a.click();
    }

    function clearLogs() {
      document.getElementById('logsContent').innerHTML = '';
    }

    function escapeHtml(text) {
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }
  </script>
</body>
</html>`);
});

// Start server
const startServer = async () => {
  await loadDeploymentStates();
  
  server.listen(PORT, () => {
    console.log(`
🚀 Agent Hosting Advanced Provisioning Server
📡 Running on http://localhost:${PORT}
📊 Active deployments: ${deploymentStates.size}
🔌 WebSocket ready for real-time updates
    `);
  });
};

// Error handling
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

// Start the server
startServer();