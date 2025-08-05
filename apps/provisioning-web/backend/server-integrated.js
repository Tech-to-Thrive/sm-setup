#!/usr/bin/env node

const express = require('express');
const crypto = require('crypto');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');
const { safeExecute, isSafeValue, sanitizeValue } = require('./utils/safe-execute');
const { validateDeploymentConfig, checkPortConflicts } = require('./validators');
const { verifyDeployment, waitForServices } = require('./post-deploy-check');
const EncryptionManager = require('./encryption-integration');
const URLValidator = require('./url-validator');
const EditionManager = require('./edition-manager');
const DeploymentLock = require('./utils/deployment-lock');
const DeploymentSnapshot = require('./utils/deployment-snapshot');
const DeploymentCheckpoint = require('./utils/deployment-checkpoint');
const DeploymentTelemetry = require('./utils/deployment-telemetry');

// Platform abstraction layer
const { platform } = require('./platform');

// Add security imports
const cookieParser = require('cookie-parser');
const ProvisioningSecurity = require('./security');
const { globalInputSanitizer, validators } = require('./middleware/input-validator');

// Initialize security before Express setup
const security = new ProvisioningSecurity();

const app = express();

// Platform-aware configuration
const PORT = process.env.PORT || 58217;  // Using unique high port to avoid conflicts
const HOST = process.env.HOST || (platform.isDesktopEnvironment() ? 'localhost' : '0.0.0.0');

// Create HTTP server for WebSocket support
const server = require('http').createServer(app);

// WebSocket implementation
const WebSocket = require('ws');
const wss = new WebSocket.Server({ server });

// Middleware
app.use(express.json({ limit: '10mb' })); // Limit payload size
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(cookieParser());
app.use(security.getSecurityHeaders());

// Global input sanitizer - first line of defense
app.use(globalInputSanitizer());

// Apply rate limiting
const { apiLimiter, deployLimiter, sensitiveLimiter } = security.getRateLimiters();

// Apply rate limiting but exclude health check and other critical endpoints
app.use('/api/', (req, res, next) => {
    // Exempt critical endpoints from rate limiting to prevent refresh loops
    const exemptPaths = ['/api/health', '/api/preflight', '/api/csrf-token'];
    
    if (exemptPaths.includes(req.path)) {
        return next();
    }
    
    return apiLimiter(req, res, next);
});

app.use('/api/deploy', deployLimiter);
app.use('/api/build', deployLimiter);
app.use('/api/validate', sensitiveLimiter);

// Serve static assets BEFORE authentication middleware
// This allows CSS, JS, and other assets to load without a token
const reactBuildPath = process.env.NODE_ENV === 'production' 
  ? path.join(__dirname, 'frontend/dist')
  : path.join(__dirname, '../frontend/dist');
  
if (fs.existsSync(reactBuildPath)) {
    console.log(`Serving React build from: ${reactBuildPath}`);
    // Serve static assets without authentication
    app.use('/assets', express.static(path.join(reactBuildPath, 'assets')));
    app.use('/favicon.ico', express.static(path.join(reactBuildPath, 'favicon.ico')));
} else {
    console.log(`React build not found at: ${reactBuildPath}`);
}

// Apply authentication (but not to static assets and public endpoints)
app.use((req, res, next) => {
    // Skip authentication for static assets and public endpoints
    const publicPaths = [
        '/assets/',
        '/favicon.ico',
        '/api/preflight',
        '/api/health',
        '/api/csrf-token'
    ];
    
    if (publicPaths.some(path => req.path.startsWith(path) || req.path === path)) {
        return next();
    }
    return security.requireToken()(req, res, next);
});

// Apply CSRF protection (but not to static assets and public endpoints)
const csrf = security.csrfProtection();
app.use((req, res, next) => {
    // Skip CSRF for static assets and public endpoints
    const publicPaths = [
        '/assets/',
        '/favicon.ico',
        '/api/preflight',
        '/api/health',
        '/api/csrf-token'
    ];
    
    if (publicPaths.some(path => req.path.startsWith(path) || req.path === path)) {
        return next();
    }
    return csrf.generate(req, res, next);
});
app.use((req, res, next) => {
    // Skip CSRF for static assets and public endpoints
    const publicPaths = [
        '/assets/',
        '/favicon.ico',
        '/api/preflight',
        '/api/health',
        '/api/csrf-token'
    ];
    
    if (publicPaths.some(path => req.path.startsWith(path) || req.path === path)) {
        return next();
    }
    return csrf.validate(req, res, next);
});

// Add CSRF token endpoint
app.get('/api/csrf-token', (req, res) => {
  res.json({ token: req.csrfToken });
});

// Storage for deployment states
const deploymentStates = new Map();
const activeSockets = new Map();

// Initialize managers
const urlValidator = new URLValidator();
const editionManager = new EditionManager();

// Deployment state persistence
const STATE_FILE = path.join(__dirname, '.provision-state.json');

// Project root detection - handle both local and Docker environments
const PROJECT_ROOT = process.env.PROJECT_ROOT || path.resolve(__dirname, '../../..');
const ENV_CONFIG_SCRIPT = path.join(PROJECT_ROOT, 'deploy/scripts/generate-env-config.sh');
const INSTALL_SCRIPT = path.join(PROJECT_ROOT, 'install.sh');
const ENV_FILE = path.join(PROJECT_ROOT, 'deploy/docker/.env');
const ENV_EXAMPLE = path.join(PROJECT_ROOT, 'deploy/docker/.env.example');

// Updated deployment steps aligned with install.sh
const DEPLOYMENT_STEPS = [
  { 
    id: 'validate', 
    name: 'Validating Environment', 
    description: 'Checking system requirements',
    icon: '✓',
    critical: true
  },
  { 
    id: 'env-config', 
    name: 'Environment Configuration', 
    description: 'Generating .env file with your settings',
    icon: '⚙️',
    critical: true
  },
  { 
    id: 'install-cleanup', 
    name: 'Cleanup', 
    description: 'Stopping services and cleaning resources',
    icon: '🧹',
    retryable: true
  },
  { 
    id: 'install-pull-core', 
    name: 'Pull Core Images', 
    description: 'Downloading PostgreSQL, Redis, MITM Proxy',
    icon: '📦',
    retryable: true,
    longRunning: true
  },
  { 
    id: 'install-pull-monitoring', 
    name: 'Pull Monitoring Stack', 
    description: 'Downloading Prometheus, Grafana, Loki',
    icon: '📊',
    retryable: true,
    longRunning: true
  },
  { 
    id: 'install-pull-apps', 
    name: 'Pull Applications', 
    description: 'Downloading n8n, GoTrue, Stack Manager',
    icon: '🚀',
    retryable: true,
    longRunning: true
  },
  { 
    id: 'install-build', 
    name: 'Build Custom Images', 
    description: 'Building project-specific Docker images',
    icon: '🔨',
    retryable: true,
    longRunning: true
  },
  { 
    id: 'install-verify-images', 
    name: 'Verify Images', 
    description: 'Ensuring all required images exist',
    icon: '🔍',
    retryable: true
  },
  { 
    id: 'install-start', 
    name: 'Start Stack', 
    description: 'Starting all services with docker compose',
    icon: '🚀',
    critical: true
  },
  { 
    id: 'install-wait', 
    name: 'Wait for Health', 
    description: 'Waiting for all services to be healthy',
    icon: '🏥',
    retryable: true
  },
  { 
    id: 'install-verify', 
    name: 'Verify Services', 
    description: 'Testing all endpoints and functionality',
    icon: '✅',
    retryable: true
  },
  { 
    id: 'install-n8n-setup', 
    name: 'Setup n8n', 
    description: 'Configuring n8n automation',
    icon: '🤖',
    optional: true
  },
  {
    id: 'verify-urls',
    name: 'Verify Service URLs',
    description: 'Checking all services are accessible',
    icon: '🌐',
    retryable: true
  }
];

// Load persisted states on startup
const loadDeploymentStates = async () => {
  try {
    const fileExists = await fsPromises.access(STATE_FILE).then(() => true).catch(() => false);
    if (fileExists) {
      const data = await fsPromises.readFile(STATE_FILE, 'utf8');
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
    const states = {};
    deploymentStates.forEach((value, key) => {
      states[key] = value;
    });
    await fsPromises.writeFile(STATE_FILE, JSON.stringify(states, null, 2));
  } catch (error) {
    console.error('Failed to save deployment states:', error);
  }
};

// Auto-shutdown configuration
const AUTO_SHUTDOWN_ENABLED = process.env.AUTO_SHUTDOWN !== 'false';
const AUTO_SHUTDOWN_DELAY = parseInt(process.env.AUTO_SHUTDOWN_DELAY) || 600000; // 10 minutes default
let shutdownTimer = null;

// Function to schedule auto-shutdown
function scheduleAutoShutdown(reason = 'Deployment completed') {
  if (!AUTO_SHUTDOWN_ENABLED) return;
  
  // Clear any existing timer
  if (shutdownTimer) {
    clearTimeout(shutdownTimer);
  }
  
  const timestamp = new Date().toISOString();
  const minutes = Math.round(AUTO_SHUTDOWN_DELAY / 60000);
  const timeDisplay = minutes >= 1 ? `${minutes} minute${minutes > 1 ? 's' : ''}` : `${AUTO_SHUTDOWN_DELAY / 1000} seconds`;
  console.log(`\n[${timestamp}] 🏁 ${reason} - Wizard will automatically shut down in ${timeDisplay}...`);
  console.log('   (Set AUTO_SHUTDOWN=false to disable auto-shutdown)');
  
  shutdownTimer = setTimeout(() => {
    console.log('\n✅ Auto-shutdown: Wizard shutting down after successful deployment');
    console.log('   To run the wizard again: setup-windows.ps1 or setup.sh');
    gracefulShutdown();
  }, AUTO_SHUTDOWN_DELAY);
}

// Function to perform graceful shutdown
function gracefulShutdown() {
  console.log('\nShutting down gracefully...');
  
  // Stop any running deployments
  deploymentStates.forEach((state, id) => {
    if (state.status === 'running') {
      // Skip creating new executor, just mark as stopped
      state.status = 'stopped';
    }
  });
  
  // Close WebSocket connections
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({ 
        type: 'server_shutdown',
        message: 'Wizard shutting down after successful deployment'
      }));
      client.close();
    }
  });
  
  // Close HTTP server
  server.close(() => {
    console.log('Server closed successfully');
    
    // Clean up PID file
    const pidFile = path.join(__dirname, '..', '..', '..', 'run', 'provisioning-wizard', 'wizard.pid');
    try {
      if (fs.existsSync(pidFile)) {
        fs.unlinkSync(pidFile);
        console.log('PID file removed');
      }
    } catch (error) {
      console.error('Failed to remove PID file:', error);
    }
    
    process.exit(0);
  });
  
  // Force exit after 5 seconds if graceful shutdown fails
  setTimeout(() => {
    console.log('Forcing shutdown...');
    process.exit(0);
  }, 5000);
}

// Deployment executor class
class DeploymentExecutor {
  constructor(deploymentId, config, resumeFromCheckpoint = null) {
    this.deploymentId = deploymentId;
    this.config = config;
    this.installProcess = null;
    this.lock = new DeploymentLock();
    this.snapshot = new DeploymentSnapshot(deploymentId);
    this.checkpoint = new DeploymentCheckpoint(deploymentId);
    this.telemetry = new DeploymentTelemetry();
    this.resumeFromCheckpoint = resumeFromCheckpoint;
    
    // Initialize state with checkpoint if resuming
    if (resumeFromCheckpoint) {
      this.state = this.initializeFromCheckpoint(resumeFromCheckpoint);
    } else {
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
  }

  sanitizeConfig(config) {
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
    // Run pre-flight resource checks before acquiring lock
    try {
      const ResourceValidator = require('./utils/resource-validator');
      const preflightChecks = await ResourceValidator.runPreflightChecks();
      
      if (!preflightChecks.passed) {
        const errorMessage = preflightChecks.summary.criticalIssues.length > 0
          ? `Pre-flight checks failed: ${preflightChecks.summary.criticalIssues.join('; ')}`
          : `Pre-flight checks completed with warnings: ${preflightChecks.summary.warnings.join('; ')}`;
        
        this.updateState({
          status: 'failed',
          error: errorMessage,
          preflightChecks: preflightChecks
        });
        
        // Only fail on critical issues, continue with warnings
        if (preflightChecks.summary.criticalIssues.length > 0) {
          throw new Error(errorMessage);
        }
      }
      
      // Log successful pre-flight checks
      this.updateLog('Pre-flight checks passed', 'success');
      this.updateLog(`Disk: ${preflightChecks.checks.disk.message}`, 'info');
      this.updateLog(`Memory: ${preflightChecks.checks.memory.message}`, 'info');
      this.updateLog(`Docker: ${preflightChecks.checks.docker.message}`, 'info');
      this.updateLog(`Network: ${preflightChecks.checks.network.message}`, 'info');
      if (preflightChecks.checks.ports.conflicts.length > 0) {
        this.updateLog(`Ports: ${preflightChecks.checks.ports.message}`, 'warning');
      }
    } catch (error) {
      this.updateState({
        status: 'failed',
        error: `Pre-flight checks failed: ${error.message}`
      });
      throw error;
    }

    // Acquire deployment lock after pre-flight checks pass
    const lockAcquired = await this.lock.acquire();
    if (!lockAcquired) {
      this.updateState({ 
        status: 'failed',
        error: 'Another deployment is already in progress. Please wait for it to complete.'
      });
      throw new Error('Another deployment is already in progress');
    }

    this.updateState({ status: 'running' });
    
    // Determine starting point
    let startStep = 0;
    if (this.resumeFromCheckpoint) {
      startStep = this.resumeFromCheckpoint.resumeFromStep;
      this.updateLog(`Resuming deployment from step ${startStep} (previously completed ${this.resumeFromCheckpoint.lastCompletedStep + 1} steps)`);
      this.broadcast({ 
        type: 'deployment-resumed',
        fromStep: startStep,
        previousSteps: this.resumeFromCheckpoint.lastCompletedStep + 1
      });
    }

    try {
      // Execute steps based on starting point
      if (startStep <= 0) {
        // Step 1: Validate environment
        await this.executeStep(0, async () => {
        // Check for required tools
        await safeExecute('which', ['docker']);
        try {
          await safeExecute('which', ['docker-compose']);
        } catch (e) {
          // Try docker compose (new syntax)
          await safeExecute('docker', ['compose', 'version']);
        }
        
        // Check if scripts exist
        if (!await this.fileExists(ENV_CONFIG_SCRIPT)) {
          throw new Error(`Environment config script not found at ${ENV_CONFIG_SCRIPT}`);
        }
        if (!await this.fileExists(INSTALL_SCRIPT)) {
          throw new Error(`Install script not found at ${INSTALL_SCRIPT}`);
        }
      });
      }

      // Step 2: Generate environment configuration
      if (startStep <= 1) {
        await this.executeStep(1, async () => {
        // Validate inputs before passing to script
        const domain = this.config.domain || 'localhost';
        const email = this.config.adminEmail;
        
        // Validate that inputs are safe
        if (!isSafeValue(domain)) {
          throw new Error('Domain contains invalid characters');
        }
        if (!isSafeValue(email)) {
          throw new Error('Email contains invalid characters');
        }
        
        const envConfigArgs = [
          '--auto-generate',
          '--domain', domain,
          '--email', email,
          '--show-credentials'
        ];

        // Handle password securely
        let passwordFile = null;
        let tempDir = null;
        if (this.config.adminPassword) {
          const os = require('os');
          tempDir = await fsPromises.mkdtemp(path.join(os.tmpdir(), 'provision-'));
          passwordFile = path.join(tempDir, 'admin.pass');
          await fsPromises.writeFile(passwordFile, this.config.adminPassword, { 
            mode: 0o600,
            flag: 'wx'
          });
          envConfigArgs.push('--password-file', passwordFile);
        }

        try {
          const { stdout, stderr } = await safeExecute(ENV_CONFIG_SCRIPT, envConfigArgs, {
            cwd: PROJECT_ROOT
          });

          if (stdout) this.log(1, stdout, 'output');
          if (stderr) this.log(1, stderr, 'warning');
        } finally {
          // Clean up temp password file
          if (passwordFile) {
            try {
              await fsPromises.unlink(passwordFile);
              await fsPromises.rmdir(tempDir);
            } catch (e) {
              console.error('Failed to cleanup password file:', e);
            }
          }
        }

        // Create encrypted backup if encryption is available
        try {
          const encryptionManager = new EncryptionManager(PROJECT_ROOT);
          const backup = await encryptionManager.createEncryptedBackup(
            ENV_FILE,
            `Provisioning deployment - ${this.config.domain || 'localhost'}`
          );
          this.log(1, `Created ${backup.encrypted ? 'encrypted' : 'unencrypted'} backup: ${backup.backupName}`, 'info');
        } catch (error) {
          this.log(1, `Backup creation warning: ${error.message}`, 'warning');
        }

        // Verify .env was created
        if (!await this.fileExists(ENV_FILE)) {
          throw new Error('.env file was not created');
        }
      });
      }

      // Steps 3-12: Run install.sh with real-time output
      // Only run if we haven't completed these steps
      if (startStep <= 11) {
        await this.runInstallScript(startStep);
      }

      // Step 13: Verify all service URLs are accessible
      if (startStep <= 12) {
        await this.executeStep(12, async () => {
        this.log(12, 'Starting service URL verification...', 'info');
        
        // Wait a bit for services to stabilize
        await new Promise(resolve => setTimeout(resolve, 5000));
        
        // Run verification
        const verification = await verifyDeployment(this.config);
        
        // Log results
        this.log(12, `Verification completed: ${verification.summary}`, 
          verification.allHealthy ? 'info' : 'warning');
        
        verification.services.forEach(service => {
          const status = service.healthy ? '✅' : '❌';
          const details = service.healthy 
            ? `(HTTP ${service.statusCode})`
            : `(${service.error || 'Not accessible'})`;
          
          this.log(12, `${status} ${service.name}: ${service.url} ${details}`, 
            service.healthy ? 'output' : 'warning');
        });
        
        // Show accessible URLs
        if (verification.allHealthy) {
          this.log(12, '\nAll services are accessible! Your stack is ready to use:', 'info');
          this.log(12, `- n8n: https://${this.config.domain || 'localhost'}:5678`, 'output');
          this.log(12, `- Grafana: http://${this.config.domain || 'localhost'}:3000`, 'output');
          this.log(12, `- Stack Manager: http://${this.config.domain || 'localhost'}:3001`, 'output');
        } else {
          // If critical services failed, throw error
          const criticalFailures = verification.services.filter(s => s.critical && !s.healthy);
          if (criticalFailures.length > 0) {
            throw new Error(`Critical services are not accessible: ${criticalFailures.map(s => s.name).join(', ')}`);
          }
        }
      });
      }

    } catch (error) {
      this.updateState({ 
        status: 'failed',
        error: error.message 
      });
      throw error;
    } finally {
      // Always release the lock
      await this.lock.release();
    }

    if (this.state.status === 'running') {
      this.updateState({
        status: 'completed',
        endTime: new Date().toISOString()
      });
      
      // Delete checkpoint on successful completion
      await this.checkpoint.deleteCheckpoint();
      
      // Trigger auto-shutdown on successful provisioning
      scheduleAutoShutdown('Deployment completed successfully');
    }
    
    // Send telemetry regardless of success/failure
    try {
      const deploymentData = await this.telemetry.collectDeploymentData(this);
      const telemetryResult = await this.telemetry.sendTelemetry(deploymentData);
      
      if (telemetryResult.success && telemetryResult.trackingId) {
        this.state.telemetryTrackingId = telemetryResult.trackingId;
        this.updateLog(`Telemetry sent successfully. Tracking ID: ${telemetryResult.trackingId}`);
      }
    } catch (telemetryError) {
      console.error('Failed to send telemetry:', telemetryError);
      // Don't fail deployment due to telemetry errors
    }
  }

  async runInstallScript() {
    return new Promise((resolve, reject) => {
      // Map install.sh steps to our UI steps
      const stepMapping = {
        'Cleanup': 2,
        'Pull Core Images': 3,
        'Pull Monitoring Stack': 4,
        'Pull Application Images': 5,
        'Build Custom Images': 6,
        'Verify Images': 7,
        'Start Stack': 8,
        'Wait for Healthy Services': 9,
        'Verify Services': 10,
        'Setup n8n': 11
      };

      const currentStepIndex = { value: 2 }; // Start with cleanup step

      // Run install.sh with --clean flag
      this.installProcess = spawn(INSTALL_SCRIPT, ['--clean', '--verbose'], {
        cwd: PROJECT_ROOT,
        env: { ...process.env, TERM: 'xterm-256color' }
      });

      // Handle stdout
      this.installProcess.stdout.on('data', (data) => {
        const output = data.toString();
        
        // Parse output to detect step changes
        Object.keys(stepMapping).forEach(stepName => {
          if (output.includes(`[${stepName}]`) || output.includes(`Starting ${stepName}`)) {
            const newStepIndex = stepMapping[stepName];
            if (newStepIndex !== currentStepIndex.value) {
              // Complete previous step
              if (currentStepIndex.value >= 2) {
                this.updateStep(currentStepIndex.value, {
                  status: 'completed',
                  progress: 100,
                  endTime: new Date().toISOString()
                });
              }
              // Start new step
              currentStepIndex.value = newStepIndex;
              this.updateStep(newStepIndex, {
                status: 'running',
                startTime: new Date().toISOString(),
                progress: 0
              });
            }
          }
        });

        // Log output to current step
        this.log(currentStepIndex.value, output.trim(), 'output');

        // Update progress based on output patterns
        if (output.includes('%')) {
          const match = output.match(/(\d+)%/);
          if (match) {
            this.updateStep(currentStepIndex.value, {
              progress: parseInt(match[1])
            });
          }
        }
      });

      // Handle stderr
      this.installProcess.stderr.on('data', (data) => {
        const error = data.toString();
        this.log(currentStepIndex.value, error.trim(), 'error');
      });

      // Handle completion
      this.installProcess.on('close', (code) => {
        if (code === 0) {
          // Complete the last step
          this.updateStep(currentStepIndex.value, {
            status: 'completed',
            progress: 100,
            endTime: new Date().toISOString()
          });
          resolve();
        } else {
          this.updateStep(currentStepIndex.value, {
            status: 'failed',
            error: {
              message: `Install script exited with code ${code}`,
              canRetry: true
            },
            endTime: new Date().toISOString()
          });
          reject(new Error(`Install script failed with exit code ${code}`));
        }
      });

      // Handle errors
      this.installProcess.on('error', (error) => {
        this.updateStep(currentStepIndex.value, {
          status: 'failed',
          error: {
            message: error.message,
            canRetry: true
          }
        });
        reject(error);
      });
    });
  }

  async executeStep(stepIndex, executor) {
    const step = this.state.steps[stepIndex];
    
    this.updateStep(stepIndex, {
      status: 'running',
      startTime: new Date().toISOString(),
      progress: 0
    });

    try {
      await executor();
      
      const duration = new Date() - new Date(step.startTime);
      this.updateStep(stepIndex, {
        status: 'completed',
        endTime: new Date().toISOString(),
        duration,
        progress: 100
      });
      
      // Create snapshot after successful step completion
      try {
        const snapshotInfo = await this.snapshot.createSnapshot(stepIndex, this.config);
        this.log(stepIndex, `Snapshot created: ${snapshotInfo.id}`, 'info');
        
        // Clean up old snapshots (keep last 5)
        await this.snapshot.cleanup(5);
      } catch (snapshotError) {
        // Log but don't fail deployment if snapshot fails
        this.log(stepIndex, `Warning: Could not create snapshot: ${snapshotError.message}`, 'warning');
      }
      
      // Create checkpoint after successful step
      try {
        const checkpointInfo = await this.checkpoint.createCheckpoint(
          stepIndex,
          this.state,
          this.state.steps[stepIndex].logs
        );
        this.log(stepIndex, `Checkpoint created for step ${stepIndex}`, 'info');
      } catch (checkpointError) {
        // Log but don't fail deployment if checkpoint fails
        this.log(stepIndex, `Warning: Could not create checkpoint: ${checkpointError.message}`, 'warning');
      }
    } catch (error) {
      this.updateStep(stepIndex, {
        status: 'failed',
        error: {
          message: error.message,
          code: error.code,
          canRetry: step.retryable
        },
        endTime: new Date().toISOString()
      });
      throw error;
    }
  }

  async fileExists(filepath) {
    try {
      await fsPromises.access(filepath);
      return true;
    } catch {
      return false;
    }
  }

  log(stepIndex, message, level = 'info') {
    const logEntry = {
      timestamp: new Date().toISOString(),
      message,
      level
    };

    if (stepIndex >= 0 && stepIndex < this.state.steps.length) {
      this.state.steps[stepIndex].logs.push(logEntry);
      
      // Trim logs if too many
      if (this.state.steps[stepIndex].logs.length > 500) {
        this.state.steps[stepIndex].logs = this.state.steps[stepIndex].logs.slice(-400);
      }
    }

    this.broadcast({
      type: 'log',
      deploymentId: this.deploymentId,
      stepIndex,
      log: logEntry
    });
  }

  updateStep(stepIndex, updates) {
    Object.assign(this.state.steps[stepIndex], updates);
    this.updateState({});
  }

  updateState(updates) {
    Object.assign(this.state, updates);
    saveDeploymentStates();
    
    this.broadcast({
      type: 'state',
      deploymentId: this.deploymentId,
      state: this.state
    });
  }

  broadcast(message) {
    const sockets = activeSockets.get(this.deploymentId) || [];
    const messageStr = JSON.stringify(message);
    
    sockets.forEach(ws => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(messageStr);
      }
    });
  }

  stop() {
    if (this.installProcess) {
      this.installProcess.kill('SIGTERM');
      this.installProcess = null;
    }
  }

  // Initialize state from checkpoint
  initializeFromCheckpoint(checkpoint) {
    const state = {
      id: this.deploymentId,
      status: 'resuming',
      currentStep: checkpoint.lastCompletedStep,
      steps: DEPLOYMENT_STEPS.map((step, index) => {
        if (index <= checkpoint.lastCompletedStep) {
          // Mark completed steps based on checkpoint
          return {
            ...step,
            status: 'completed',
            logs: [],
            error: null,
            progress: 100,
            ...(checkpoint.stepResults[index] || {})
          };
        } else {
          // Remaining steps are pending
          return {
            ...step,
            status: 'pending',
            logs: [],
            error: null,
            progress: 0,
            startTime: null,
            endTime: null,
            duration: null
          };
        }
      }),
      startTime: checkpoint.metadata.deploymentStartTime,
      config: { ...this.config, ...checkpoint.config },
      resumedFrom: checkpoint.lastCompletedStep + 1,
      previousLogs: checkpoint.previousLogs || []
    };

    // Add previous logs to completed steps
    if (checkpoint.previousLogs) {
      checkpoint.previousLogs.forEach(log => {
        if (log.step !== undefined && state.steps[log.step]) {
          state.steps[log.step].logs.push(log);
        }
      });
    }

    return state;
  }

  // Check if deployment can be resumed
  async canResume() {
    return await this.checkpoint.canResume();
  }
}

// WebSocket handling
wss.on('connection', (ws) => {
  let deploymentId = null;

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      
      if (data.type === 'subscribe' && data.deploymentId) {
        deploymentId = data.deploymentId;
        
        // Add to active sockets
        if (!activeSockets.has(deploymentId)) {
          activeSockets.set(deploymentId, []);
        }
        activeSockets.get(deploymentId).push(ws);
        
        // Send current state
        const state = deploymentStates.get(deploymentId);
        if (state) {
          ws.send(JSON.stringify({
            type: 'state',
            deploymentId,
            state
          }));
        }
      }
    } catch (error) {
      console.error('WebSocket message error:', error);
    }
  });

  ws.on('close', () => {
    if (deploymentId && activeSockets.has(deploymentId)) {
      const sockets = activeSockets.get(deploymentId);
      const index = sockets.indexOf(ws);
      if (index > -1) {
        sockets.splice(index, 1);
      }
      if (sockets.length === 0) {
        activeSockets.delete(deploymentId);
      }
    }
  });
});

// API Routes
app.get('/api/deployments/:id', (req, res) => {
  const state = deploymentStates.get(req.params.id);
  if (!state) {
    return res.status(404).json({ error: 'Deployment not found' });
  }
  res.json(state);
});

app.post('/api/deployments/:id/retry/:stepIndex', async (req, res) => {
  const { id, stepIndex } = req.params;
  const state = deploymentStates.get(id);
  
  if (!state) {
    return res.status(404).json({ error: 'Deployment not found' });
  }
  
  const step = state.steps[parseInt(stepIndex)];
  if (!step || !step.retryable) {
    return res.status(400).json({ error: 'Step cannot be retried' });
  }
  
  // For now, restart the entire install process
  // In future, could implement step-specific retry
  res.json({ message: 'Please restart the deployment to retry' });
});

// Validation endpoint
app.post('/api/validate', validators.deployment, async (req, res) => {
  const config = req.validatedInputs || req.body;
  
  try {
    const validation = await validateDeploymentConfig(config);
    res.json(validation);
  } catch (error) {
    res.status(500).json({
      valid: false,
      errors: [`Validation error: ${error.message}`],
      warnings: [],
      info: []
    });
  }
});

// Check port conflicts endpoint
app.get('/api/check-ports', async (req, res) => {
  try {
    const conflicts = await checkPortConflicts({});
    res.json({ conflicts });
  } catch (error) {
    res.status(500).json({ 
      error: 'Failed to check ports',
      message: error.message 
    });
  }
});

app.post('/api/deploy', deployLimiter, validators.deployment, async (req, res) => {
  const deploymentId = crypto.randomBytes(16).toString('hex');
  const config = req.validatedInputs || req.body;

  // Validate before deployment
  try {
    const validation = await validateDeploymentConfig(config);
    if (!validation.valid) {
      return res.status(400).json({
        error: 'Validation failed',
        validation
      });
    }
    
    // Include validation warnings in response
    if (validation.warnings.length > 0) {
      console.log('Deployment warnings:', validation.warnings);
    }
  } catch (error) {
    return res.status(500).json({
      error: 'Validation error',
      message: error.message
    });
  }

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

// Verify deployment endpoint - check if services are accessible
app.post('/api/verify-deployment', async (req, res) => {
  const { domain } = req.body;
  
  try {
    const config = { domain: domain || 'localhost' };
    const results = await verifyDeployment(config);
    res.json(results);
  } catch (error) {
    res.status(500).json({
      error: 'Verification failed',
      message: error.message
    });
  }
});

// Encryption status endpoint
app.get('/api/encryption/status', async (req, res) => {
  try {
    const encryptionManager = new EncryptionManager(PROJECT_ROOT);
    const dependencies = await encryptionManager.checkDependencies();
    const publicKey = await encryptionManager.getPublicKey();
    
    res.json({
      available: dependencies.sops && dependencies.age,
      configured: dependencies.ageKeysExist,
      dependencies,
      publicKey
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to check encryption status',
      message: error.message
    });
  }
});

// List backups endpoint
app.get('/api/backups', async (req, res) => {
  try {
    const encryptionManager = new EncryptionManager(PROJECT_ROOT);
    const backups = await encryptionManager.listBackups();
    res.json({ backups });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to list backups',
      message: error.message
    });
  }
});

// Restore backup endpoint
app.post('/api/backups/restore', async (req, res) => {
  const { backupName } = req.body;
  
  if (!backupName) {
    return res.status(400).json({ error: 'Backup name required' });
  }
  
  try {
    const encryptionManager = new EncryptionManager(PROJECT_ROOT);
    const result = await encryptionManager.restoreBackup(backupName, ENV_FILE);
    res.json({
      success: true,
      message: `Restored ${result.encrypted ? 'encrypted' : 'unencrypted'} backup successfully`,
      backupName
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to restore backup',
      message: error.message
    });
  }
});

// Install encryption tools endpoint
app.post('/api/encryption/install', async (req, res) => {
  try {
    const encryptionManager = new EncryptionManager(PROJECT_ROOT);
    const success = await encryptionManager.installTools();
    
    if (success) {
      // Setup encryption after installation
      const publicKey = await encryptionManager.setupEncryption();
      res.json({
        success: true,
        message: 'Encryption tools installed and configured',
        publicKey
      });
    } else {
      res.status(500).json({
        error: 'Failed to install encryption tools'
      });
    }
  } catch (error) {
    res.status(500).json({
      error: 'Failed to install encryption tools',
      message: error.message
    });
  }
});

// Check for existing configuration
app.get('/api/check-existing', async (req, res) => {
  try {
    const envExists = await fsPromises.access(ENV_FILE).then(() => true).catch(() => false);
    const envExampleExists = await fsPromises.access(ENV_EXAMPLE).then(() => true).catch(() => false);
    
    let existingConfig = null;
    if (envExists) {
      try {
        const envContent = await fsPromises.readFile(ENV_FILE, 'utf8');
        const lines = envContent.split('\n');
        const config = {};
        
        // Parse key environment variables
        lines.forEach(line => {
          if (line.includes('=') && !line.startsWith('#')) {
            const [key, ...valueParts] = line.split('=');
            const value = valueParts.join('=').trim();
            if (key && value) {
              config[key.trim()] = value;
            }
          }
        });
        
        existingConfig = {
          domain: config.DOMAIN_NAME || config.DOMAIN || 'localhost',
          adminEmail: config.MASTER_ADMIN_EMAIL || config.ADMIN_EMAIL,
          hasSSL: !!(config.SSL_PROVIDER && config.SSL_PROVIDER !== 'none'),
          sslProvider: config.SSL_PROVIDER,
          stackConfigured: !!(config.POSTGRES_PASSWORD && config.JWT_SECRET)
        };
      } catch (e) {
        console.error('Error parsing .env file:', e);
      }
    }
    
    // Check for running containers
    let runningContainers = [];
    try {
      const { stdout } = await safeExecute('docker', [
        'ps', 
        '--format', '{{.Names}}',
        '--filter', 'name=ai-stack-',
        '--filter', 'name=n8n-monitoring'
      ]);
      if (stdout.trim()) {
        runningContainers = stdout.trim().split('\n');
      }
    } catch (e) {
      // Ignore errors
    }
    
    res.json({
      envExists,
      envExampleExists,
      existingConfig,
      runningContainers,
      canProceed: envExampleExists
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to check existing configuration',
      message: error.message
    });
  }
});

// Real-time URL validation endpoint
app.post('/api/validate-url', async (req, res) => {
  const { url, checkPropagation, serverIPs } = req.body;
  
  try {
    const validation = await urlValidator.validateURL(url, {
      checkPointsToServer: checkPropagation,
      serverIPs: serverIPs || [],
      allowUnresolved: false,
      allowExternal: false
    });
    
    res.json(validation);
  } catch (error) {
    res.status(500).json({
      error: 'URL validation failed',
      message: error.message
    });
  }
});

// Domain validation endpoint
app.post('/api/validate/domain', validators.validateDomain, async (req, res) => {
  const { domain } = req.body;
  
  try {
    // Basic domain validation
    if (!domain || domain.trim() === '') {
      return res.json({
        valid: false,
        message: 'Domain is required'
      });
    }
    
    // Allow localhost for local development
    if (domain === 'localhost' || domain === 'localhost.dev') {
      return res.json({
        valid: true,
        message: 'Valid local domain'
      });
    }
    
    // Check domain format
    const domainRegex = /^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$/;
    if (!domainRegex.test(domain)) {
      return res.json({
        valid: false,
        message: 'Invalid domain format. Use format like example.com'
      });
    }
    
    // Additional checks could include DNS lookup
    const dns = require('dns').promises;
    try {
      await dns.lookup(domain);
      res.json({
        valid: true,
        message: 'Domain is valid and resolves'
      });
    } catch (dnsError) {
      res.json({
        valid: true, // Domain format is valid even if not resolving yet
        message: 'Domain format is valid (DNS not configured yet)'
      });
    }
    
  } catch (error) {
    res.status(500).json({
      valid: false,
      message: error.message
    });
  }
});

// Cloudflare validation endpoint
app.post('/api/validate/cloudflare', validators.validateCloudflare, async (req, res) => {
  const { cloudflareApiToken, cloudflareZoneId } = req.body;
  
  try {
    if (!cloudflareApiToken || !cloudflareZoneId) {
      return res.json({
        valid: false,
        message: 'API token and Zone ID are required'
      });
    }
    
    // Basic validation - in production you'd verify with Cloudflare API
    const tokenRegex = /^[a-zA-Z0-9_-]{40,}$/;
    const zoneIdRegex = /^[a-f0-9]{32}$/;
    
    if (!tokenRegex.test(cloudflareApiToken)) {
      return res.json({
        valid: false,
        message: 'Invalid API token format'
      });
    }
    
    if (!zoneIdRegex.test(cloudflareZoneId)) {
      return res.json({
        valid: false,
        message: 'Invalid Zone ID format (should be 32 hex characters)'
      });
    }
    
    res.json({
      valid: true,
      message: 'Cloudflare credentials format is valid'
    });
    
  } catch (error) {
    res.status(500).json({
      valid: false,
      message: error.message
    });
  }
});

// URL validation endpoint
app.post('/api/validate/url', async (req, res) => {
  const { url, edition } = req.body;
  
  try {
    if (!url || url.trim() === '') {
      return res.json({
        valid: false,
        message: 'URL is required'
      });
    }
    
    // For localhost URLs
    if (url.includes('localhost')) {
      return res.json({
        valid: true,
        message: 'Valid local URL'
      });
    }
    
    // Basic URL format validation
    const urlRegex = /^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?(\.[a-zA-Z]{2,})?$/;
    if (!urlRegex.test(url)) {
      return res.json({
        valid: false,
        message: 'Invalid URL format'
      });
    }
    
    res.json({
      valid: true,
      message: 'URL format is valid'
    });
    
  } catch (error) {
    res.status(500).json({
      valid: false,
      message: error.message
    });
  }
});

// Service URL validation endpoint
app.post('/api/validate/service-url', validators.validateServiceUrl, async (req, res) => {
  const { url, service, edition, sslProvider } = req.body;
  
  try {
    if (!url || url.trim() === '') {
      return res.json({
        valid: false,
        message: 'Service URL is required'
      });
    }
    
    // Use the URLValidator for comprehensive checks
    const validation = await urlValidator.validateURL(url, {
      checkPointsToServer: true,
      allowUnresolved: sslProvider === 'cloudflare-tunnel' || sslProvider === 'cloudflare-dns', // Allow unresolved for Cloudflare
      serverIPs: [] // Will auto-detect
    });
    
    // For localhost URLs
    if (validation.isLocal) {
      return res.json({
        valid: true,
        message: `Valid local ${service} URL`,
        isLocal: true
      });
    }
    
    // Check format
    if (!validation.checks.format.valid) {
      return res.json({
        valid: false,
        message: validation.checks.format.error || 'Invalid URL format'
      });
    }
    
    // Check DNS resolution
    if (validation.checks.dns && !validation.checks.dns.resolved) {
      if (sslProvider === 'cloudflare-tunnel' || sslProvider === 'cloudflare-dns') {
        // For Cloudflare, unresolved is OK (will be configured later)
        return res.json({
          valid: true,
          message: `${service} URL format is valid (DNS will be configured via Cloudflare)`,
          warning: 'DNS not yet configured',
          needsConfiguration: true
        });
      } else {
        return res.json({
          valid: false,
          message: `Domain does not resolve. Please configure DNS for ${url}`,
          needsConfiguration: true
        });
      }
    }
    
    // Check if points to server (for non-Cloudflare)
    if (validation.checks.pointsToServer && sslProvider !== 'cloudflare-tunnel' && sslProvider !== 'cloudflare-dns') {
      if (!validation.checks.pointsToServer.pointsToServer) {
        const serverIPs = validation.checks.pointsToServer.serverIPs || [];
        return res.json({
          valid: false,
          message: `Domain resolves but does not point to this server. Point DNS A record to: ${serverIPs.join(' or ')}`,
          serverIPs: serverIPs,
          currentIPs: validation.checks.pointsToServer.domainIPs || []
        });
      }
    }
    
    res.json({
      valid: true,
      message: `${service} URL is properly configured`,
      dns: validation.checks.dns,
      serverCheck: validation.checks.pointsToServer
    });
    
  } catch (error) {
    res.status(500).json({
      valid: false,
      message: error.message
    });
  }
});

// Batch URL validation endpoint
app.post('/api/validate-urls', async (req, res) => {
  const { urls, edition } = req.body;
  
  try {
    // Validate against edition limits
    const editionValidation = editionManager.validateConfigForEdition(
      { domains: Object.keys(urls), useSubdomains: true },
      edition
    );
    
    if (!editionValidation.valid) {
      return res.status(400).json(editionValidation);
    }
    
    const validation = await urlValidator.validateServiceURLs(urls, {
      checkPointsToServer: true,
      allowUnresolved: false
    });
    
    res.json(validation);
  } catch (error) {
    res.status(500).json({
      error: 'URL validation failed',
      message: error.message
    });
  }
});

// Monitor DNS propagation endpoint
app.post('/api/monitor-propagation', async (req, res) => {
  const { hostname, targetIPs } = req.body;
  const clientId = req.headers['x-client-id'] || 'default';
  
  // Set up SSE headers
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });
  
  // Monitor propagation
  urlValidator.monitorPropagation(hostname, targetIPs, (status) => {
    res.write(`data: ${JSON.stringify(status)}\n\n`);
    
    if (status.pointsToServer || status.error || 
        status.attempt >= status.maxAttempts) {
      res.end();
    }
  });
  
  req.on('close', () => {
    console.log('Propagation monitoring closed for', hostname);
  });
});

// Get subdomain suggestions
app.post('/api/suggest-subdomains', (req, res) => {
  const { baseDomain } = req.body;
  
  if (!baseDomain) {
    return res.status(400).json({ error: 'Base domain required' });
  }
  
  const suggestions = urlValidator.generateSubdomainSuggestions(baseDomain, {
    stackManager: true,
    grafana: true,
    n8n: true,
    prometheus: true
  });
  
  res.json({ suggestions });
});

// Edition endpoints
app.get('/api/editions', (req, res) => {
  res.json({
    editions: editionManager.editions,
    comparison: editionManager.getEditionComparison()
  });
});

app.post('/api/editions/recommend', (req, res) => {
  const requirements = req.body;
  const recommendation = editionManager.recommendEdition(requirements);
  res.json(recommendation);
});

app.post('/api/editions/validate', (req, res) => {
  const { config, edition } = req.body;
  const validation = editionManager.validateConfigForEdition(config, edition);
  res.json(validation);
});

app.get('/api/editions/:edition/features', (req, res) => {
  const { edition } = req.params;
  const editionData = editionManager.getEdition(edition);
  res.json(editionData);
});

// Check server IPs
app.get('/api/server-ips', async (req, res) => {
  try {
    const ips = await urlValidator.getServerPublicIPs();
    res.json({ ips });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to get server IPs',
      message: error.message
    });
  }
});

// Cloudflare permissions info endpoint
app.get('/api/cloudflare/permissions', (req, res) => {
  res.json({
    tunnel: {
      name: 'Cloudflare Tunnel',
      description: 'Zero-trust networking without exposing ports',
      requirements: {
        token: {
          type: 'Tunnel Token',
          location: 'one.dash.cloudflare.com → Access → Tunnels → Create/Configure Tunnel',
          permissions: [
            'Tunnel:Read',
            'Tunnel:Write',
            'Account:Read'
          ],
          steps: [
            'Log in to Cloudflare One dashboard',
            'Navigate to Access > Tunnels',
            'Create a new tunnel or use existing',
            'Copy the tunnel token from configuration',
            'Token includes all necessary permissions'
          ]
        }
      },
      benefits: [
        'No inbound ports required',
        'Built-in DDoS protection',
        'Automatic SSL/TLS',
        'Global edge network',
        'Access policies support'
      ]
    },
    api: {
      name: 'Cloudflare API',
      description: 'Traditional DNS management with API',
      requirements: {
        token: {
          type: 'API Token',
          location: 'dash.cloudflare.com/profile/api-tokens',
          permissions: [
            'Zone:DNS:Read',
            'Zone:DNS:Edit',
            'Zone:Zone:Read',
            'Zone:SSL and Certificates:Read'
          ],
          steps: [
            'Go to Cloudflare Dashboard',
            'Click profile icon > My Profile',
            'Go to API Tokens tab',
            'Create Token > Edit zone DNS template',
            'Select specific zones or all zones',
            'Add required permissions listed above',
            'Create token and copy immediately'
          ]
        },
        zoneId: {
          type: 'Zone ID',
          location: 'Cloudflare Dashboard > Domain > Overview (right sidebar)',
          description: 'Unique identifier for your domain'
        }
      },
      benefits: [
        'Full DNS control',
        'Programmatic updates',
        'Multiple record types',
        'Advanced configurations'
      ]
    }
  });
});

// Background docker build trigger
app.post('/api/build/start', async (req, res) => {
  const { deploymentId } = req.body;
  
  try {
    // Start background build process
    const buildProcess = spawn('docker', ['compose', 'build'], {
      cwd: PROJECT_ROOT,
      detached: true,
      stdio: 'pipe'
    });
    
    buildProcess.unref();
    
    // Store build process reference
    if (deploymentId && deploymentStates.has(deploymentId)) {
      const state = deploymentStates.get(deploymentId);
      state.buildProcess = buildProcess.pid;
      deploymentStates.set(deploymentId, state);
    }
    
    res.json({
      success: true,
      message: 'Background build started',
      pid: buildProcess.pid
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to start background build',
      message: error.message
    });
  }
});

// DNS check endpoint for review step
app.post('/api/dns/check', async (req, res) => {
  const { domains } = req.body;
  
  try {
    const results = {};
    const serverIPs = await urlValidator.getServerPublicIPs();
    
    for (const domain of domains) {
      if (!domain || domain.includes('localhost')) {
        results[domain] = {
          propagated: true,
          isLocal: true,
          message: 'Local domain'
        };
        continue;
      }
      
      try {
        // Check DNS resolution
        const dnsCheck = await urlValidator.checkDNSResolution(domain);
        
        if (dnsCheck.resolved) {
          // Check if points to server
          const serverCheck = await urlValidator.checkDomainPointsToServer(domain, serverIPs);
          
          results[domain] = {
            propagated: true,
            resolved: true,
            ip: dnsCheck.addresses[0],
            ips: dnsCheck.addresses,
            pointsToServer: serverCheck.pointsToServer,
            serverIPs: serverIPs
          };
        } else {
          results[domain] = {
            propagated: false,
            resolved: false,
            message: dnsCheck.error || 'Domain not found'
          };
        }
      } catch (error) {
        results[domain] = {
          propagated: false,
          error: error.message
        };
      }
    }
    
    res.json({
      domains: results,
      serverIPs: serverIPs,
      allPropagated: Object.values(results).every(r => r.propagated),
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    res.status(500).json({
      error: 'DNS check failed',
      message: error.message
    });
  }
});

// Download deployment logs
app.get('/api/deployments/:id/logs/download', async (req, res) => {
  try {
    const deploymentId = req.params.id;
    const { type = 'full' } = req.query; // full, anonymized, or report
    
    // Get deployment state
    const deployment = deploymentStates.get(deploymentId);
    if (!deployment) {
      return res.status(404).json({
        error: 'Deployment not found'
      });
    }
    
    // Create telemetry instance to generate logs
    const telemetry = new DeploymentTelemetry();
    const deploymentData = await telemetry.collectDeploymentData(deployment);
    
    // Set appropriate headers
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    
    if (type === 'report') {
      // Send JSON report
      const report = telemetry.anonymizer.generateAnonymizedReport(deploymentData);
      res.setHeader('Content-Type', 'application/json');
      res.setHeader('Content-Disposition', `attachment; filename="deployment-${deploymentId}-report-${timestamp}.json"`);
      res.json(report);
    } else {
      // Send text log
      let logContent;
      let filename;
      
      if (type === 'anonymized') {
        logContent = telemetry.generateAnonymizedLog(deploymentData);
        filename = `deployment-${deploymentId}-anonymized-${timestamp}.log`;
      } else {
        logContent = telemetry.generateFullLog(deploymentData);
        filename = `deployment-${deploymentId}-full-${timestamp}.log`;
      }
      
      res.setHeader('Content-Type', 'text/plain');
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      res.send(logContent);
    }
  } catch (error) {
    console.error('Failed to generate deployment logs:', error);
    res.status(500).json({
      error: 'Failed to generate logs',
      message: error.message
    });
  }
});

// Get deployment telemetry status
app.get('/api/deployments/:id/telemetry', async (req, res) => {
  try {
    const deploymentId = req.params.id;
    
    const deployment = deploymentStates.get(deploymentId);
    if (!deployment) {
      return res.status(404).json({
        error: 'Deployment not found'
      });
    }
    
    res.json({
      deploymentId,
      telemetryEnabled: true,
      trackingId: deployment.state.telemetryTrackingId || null,
      endpoint: 'https://n8n.nsttek.cloud/workflows/sm-event-montoring'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to get telemetry status',
      message: error.message
    });
  }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    activeDeployments: deploymentStates.size,
    activeSockets: activeSockets.size,
    edition: process.env.EDITION || 'community'
  });
});

// Deployment lock status endpoint
app.get('/api/deployment/lock-status', async (req, res) => {
  const lock = new DeploymentLock();
  const status = await lock.getStatus();
  res.json(status);
});

// Pre-flight resource checks endpoint
app.get('/api/preflight', async (req, res) => {
  try {
    const ResourceValidator = require('./utils/resource-validator');
    const checks = await ResourceValidator.runPreflightChecks();
    
    // Set appropriate status code based on results
    const statusCode = checks.passed ? 200 : 
                      checks.summary.criticalIssues.length > 0 ? 503 : 200;
    
    res.status(statusCode).json(checks);
  } catch (error) {
    console.error('Pre-flight check error:', error);
    res.status(500).json({
      passed: false,
      error: error.message,
      summary: {
        criticalIssues: ['Failed to run pre-flight checks'],
        warnings: [],
        message: `Pre-flight checks failed: ${error.message}`
      }
    });
  }
});

// List available snapshots for a deployment
app.get('/api/deployments/:id/snapshots', async (req, res) => {
  try {
    const deploymentId = req.params.id;
    const snapshot = new DeploymentSnapshot(deploymentId);
    const snapshots = await snapshot.listSnapshots();
    
    res.json({
      deploymentId,
      snapshots,
      count: snapshots.length
    });
  } catch (error) {
    console.error('Failed to list snapshots:', error);
    res.status(500).json({
      error: 'Failed to list snapshots',
      message: error.message
    });
  }
});

// Rollback to a specific snapshot
app.post('/api/deployments/:id/rollback', async (req, res) => {
  try {
    const deploymentId = req.params.id;
    const { snapshotId } = req.body;
    
    if (!snapshotId) {
      return res.status(400).json({
        error: 'Snapshot ID is required'
      });
    }
    
    // Get deployment state
    const deployment = deploymentStates.get(deploymentId);
    if (!deployment) {
      return res.status(404).json({
        error: 'Deployment not found'
      });
    }
    
    // Update deployment state
    deployment.state.status = 'rolling-back';
    deployment.updateState({});
    
    // Perform rollback
    const snapshot = new DeploymentSnapshot(deploymentId);
    const result = await snapshot.rollback(snapshotId);
    
    // Update deployment state based on result
    if (result.success) {
      deployment.state.status = 'rolled-back';
      deployment.state.currentStep = result.snapshot.step;
      deployment.updateState({
        rollbackInfo: {
          snapshotId,
          timestamp: new Date().toISOString(),
          toStep: result.snapshot.step
        }
      });
    } else {
      deployment.state.status = 'rollback-failed';
      deployment.updateState({
        error: result.message
      });
    }
    
    res.json(result);
  } catch (error) {
    console.error('Rollback failed:', error);
    res.status(500).json({
      error: 'Rollback failed',
      message: error.message
    });
  }
});

// GitHub authentication endpoints
app.post('/api/github/device-auth', async (req, res) => {
  try {
    // Use platform abstraction to execute gh CLI command
    const result = await platform.executeCommand('gh auth login --web --skip-ssh-key', {
      env: { ...process.env, GH_PROMPT: 'disabled' }
    });
    
    // Extract device code from output
    const deviceCodeMatch = result.stdout.match(/Device code: ([A-Z0-9-]+)/);
    const deviceCode = deviceCodeMatch ? deviceCodeMatch[1] : null;
    
    if (deviceCode) {
      res.json({
        success: true,
        deviceCode,
        verificationUrl: 'https://github.com/login/device',
        message: 'Please visit the verification URL and enter the device code'
      });
    } else {
      // Try device flow directly
      const deviceResult = await platform.executeCommand('gh auth login --device', {
        env: { ...process.env, GH_PROMPT: 'disabled' }
      });
      
      const codeMatch = deviceResult.stdout.match(/code: ([A-Z0-9-]+)/);
      res.json({
        success: true,
        deviceCode: codeMatch ? codeMatch[1] : 'Check terminal output',
        verificationUrl: 'https://github.com/login/device',
        message: 'Please check the terminal for the device code'
      });
    }
  } catch (error) {
    res.status(500).json({
      error: 'Failed to initiate GitHub authentication',
      message: error.message
    });
  }
});

// Check GitHub authentication status
app.get('/api/github/auth-status', async (req, res) => {
  try {
    const result = await platform.executeCommand('gh auth status');
    const isAuthenticated = result.success && result.stdout.includes('Logged in');
    
    if (isAuthenticated) {
      // Get authenticated user info
      const userResult = await platform.executeCommand('gh api user');
      const userInfo = userResult.success ? JSON.parse(userResult.stdout) : null;
      
      res.json({
        authenticated: true,
        username: userInfo?.login,
        name: userInfo?.name,
        email: userInfo?.email
      });
    } else {
      res.json({
        authenticated: false
      });
    }
  } catch (error) {
    res.json({
      authenticated: false,
      error: error.message
    });
  }
});

// List GitHub repositories
app.get('/api/github/repositories', async (req, res) => {
  try {
    // Check authentication first
    const authResult = await platform.executeCommand('gh auth status');
    if (!authResult.success || !authResult.stdout.includes('Logged in')) {
      return res.status(401).json({
        error: 'Not authenticated with GitHub'
      });
    }
    
    // List repositories
    const reposResult = await platform.executeCommand(
      'gh repo list --limit 100 --json name,description,isPrivate,url'
    );
    
    if (reposResult.success) {
      const repos = JSON.parse(reposResult.stdout);
      res.json({
        success: true,
        repositories: repos
      });
    } else {
      res.status(500).json({
        error: 'Failed to list repositories',
        message: reposResult.error
      });
    }
  } catch (error) {
    res.status(500).json({
      error: 'Failed to list repositories',
      message: error.message
    });
  }
});

// Clone GitHub repository
app.post('/api/github/clone', validators.validateGitHubClone, async (req, res) => {
  try {
    const { repositoryUrl, targetPath } = req.body;
    
    // Validate repository URL format
    if (!repositoryUrl.match(/^https:\/\/github\.com\/[\w-]+\/[\w-]+$/)) {
      return res.status(400).json({
        error: 'Invalid GitHub repository URL format'
      });
    }
    
    // Extract repo path from URL
    const repoPath = repositoryUrl.replace('https://github.com/', '');
    
    // Check if user has access to the repository
    const accessResult = await platform.executeCommand(`gh repo view ${repoPath}`);
    if (!accessResult.success) {
      return res.status(403).json({
        error: 'Cannot access repository',
        message: 'Please ensure you have access to this repository'
      });
    }
    
    // Determine target directory
    const cloneDir = targetPath || path.join('/opt', path.basename(repositoryUrl, '.git'));
    
    // Check if directory already exists
    if (fs.existsSync(cloneDir)) {
      const backupDir = `${cloneDir}.backup.${Date.now()}`;
      await fsPromises.rename(cloneDir, backupDir);
    }
    
    // Clone the repository
    const cloneResult = await platform.executeCommand(
      `gh repo clone ${repoPath} ${cloneDir}`
    );
    
    if (cloneResult.success) {
      res.json({
        success: true,
        message: 'Repository cloned successfully',
        path: cloneDir
      });
    } else {
      res.status(500).json({
        error: 'Failed to clone repository',
        message: cloneResult.error
      });
    }
  } catch (error) {
    res.status(500).json({
      error: 'Failed to clone repository',
      message: error.message
    });
  }
});

// System validation endpoint
app.get('/api/system/validate', async (req, res) => {
  try {
    const validation = {
      platform: platform.getPlatformName(),
      checks: {}
    };
    
    // Check disk space
    const dfResult = await platform.executeCommand('df -BG /opt');
    if (dfResult.success) {
      const spaceMatch = dfResult.stdout.match(/(\d+)G\s+\d+%/);
      validation.checks.diskSpace = {
        available: spaceMatch ? parseInt(spaceMatch[1]) : 0,
        required: 20,
        status: spaceMatch && parseInt(spaceMatch[1]) >= 20 ? 'pass' : 'fail'
      };
    }
    
    // Check memory
    const memResult = await platform.executeCommand('free -g');
    if (memResult.success) {
      const memMatch = memResult.stdout.match(/Mem:\s+(\d+)/);
      validation.checks.memory = {
        total: memMatch ? parseInt(memMatch[1]) : 0,
        required: 4,
        status: memMatch && parseInt(memMatch[1]) >= 4 ? 'pass' : 'fail'
      };
    }
    
    // Check Docker
    const dockerInfo = await platform.getDockerInfo();
    validation.checks.docker = {
      installed: !!dockerInfo.version,
      running: dockerInfo.running,
      status: dockerInfo.running ? 'pass' : 'fail'
    };
    
    // Check ports
    const ports = [8080, 80, 443, 3000, 5678, 9090];
    validation.checks.ports = {};
    
    for (const port of ports) {
      const available = await platform.isPortAvailable(port);
      validation.checks.ports[port] = {
        available,
        status: available || port !== 8080 ? 'pass' : 'fail'
      };
    }
    
    // Overall status
    validation.status = Object.values(validation.checks).every(
      check => check.status === 'pass'
    ) ? 'pass' : 'fail';
    
    res.json(validation);
  } catch (error) {
    res.status(500).json({
      error: 'System validation failed',
      message: error.message
    });
  }
});

// Serve static logo image
app.get('/logo.png', (req, res) => {
  const logoPath = path.join(__dirname, 'stack-master-logo.png');
  res.sendFile(logoPath, (err) => {
    if (err) {
      console.error('Error serving logo:', err);
      res.status(404).send('Logo not found');
    }
  });
});

// Static files are already served before authentication middleware

// Serve the UI - React Only
app.get('/', (req, res) => {
  // Check if user has valid token
  const token = req.query.token || req.cookies?.setupToken;
  const validation = security.validateToken(token);
  
  if (!validation.valid) {
    // If token was provided but invalid, redirect with error
    if (token && token !== '') {
      return res.redirect('/?error=' + encodeURIComponent(validation.error || 'Invalid token'));
    }
    
    // Serve welcome page if no token provided
    const welcomePath = path.join(__dirname, 'welcome.html');
    if (fs.existsSync(welcomePath)) {
      return res.sendFile(welcomePath);
    }
  }
  
  // Valid token - set cookie for subsequent requests
  if (token && validation.valid && !req.cookies?.setupToken) {
    res.cookie('setupToken', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 60 * 60 * 1000 // 1 hour
    });
  }
  
  const reactIndexPath = path.join(reactBuildPath, 'index.html');
  
  // Serve React UI only
  if (fs.existsSync(reactIndexPath)) {
    res.sendFile(reactIndexPath);
  } else {
    // Fallback if React build not found
    console.error('React build not found! Run: npm run build in frontend directory');
    res.status(500).send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AI Stack Masters - Build Error</title>
  <style>
    body { 
      font-family: system-ui; 
      background: #0a0a0a; 
      color: #fff; 
      padding: 40px; 
      text-align: center; 
    }
    .error-container {
      max-width: 600px;
      margin: 0 auto;
      background: #1a1a1a;
      padding: 40px;
      border-radius: 15px;
      border: 2px solid #ff4444;
    }
    h1 { color: #ff4444; margin-bottom: 20px; }
    p { margin: 15px 0; }
    code { 
      background: #333; 
      padding: 2px 8px; 
      border-radius: 4px; 
      color: #00d4ff; 
    }
  </style>
</head>
<body>
  <div class="error-container">
    <h1>🚫 React Build Missing</h1>
    <p>The React UI build was not found. Please build the frontend:</p>
    <p><code>cd apps/provisioning-web/frontend && npm run build</code></p>
    <p>Then restart the server to see the Stack Builder interface.</p>
  </div>
</body>
</html>`);
  }
});

// Helper function to display access URLs
function displayAccessUrls() {
  console.log('\n════════════════════════════════════════════════════════');
  console.log('🚀 Stack Masters Setup Wizard Ready!');
  console.log('════════════════════════════════════════════════════════');
  
  if (HOST === '0.0.0.0') {
    console.log('\n📡 Access the wizard from:');
    console.log(`   • This machine: http://localhost:${PORT}`);
    
    // Show all network interfaces
    const interfaces = os.networkInterfaces();
    Object.keys(interfaces).forEach(name => {
      interfaces[name].forEach(iface => {
        if (iface.family === 'IPv4' && !iface.internal) {
          console.log(`   • Local network: http://${iface.address}:${PORT}`);
        }
      });
    });
    
    // Show public IP if available
    const publicIP = process.env.PUBLIC_IP;
    if (publicIP) {
      console.log(`   • Internet: http://${publicIP}:${PORT}`);
    }
  } else {
    console.log(`\n📡 Access the wizard at: http://localhost:${PORT}`);
  }
  
  console.log('\n⚠️  Keep this terminal open while using the wizard');
  console.log('════════════════════════════════════════════════════════\n');
}

// Start server
loadDeploymentStates().then(() => {
  server.listen(PORT, HOST, () => {
    displayAccessUrls();
    
    // Write PID file for stop scripts
    const pidFile = path.join(__dirname, '..', '..', '..', 'run', 'provisioning-wizard', 'wizard.pid');
    try {
      const pidDir = path.dirname(pidFile);
      if (!fs.existsSync(pidDir)) {
        fs.mkdirSync(pidDir, { recursive: true });
      }
      fs.writeFileSync(pidFile, process.pid.toString());
      console.log(`Process ID ${process.pid} written to wizard.pid`);
    } catch (error) {
      console.error('Failed to write PID file:', error);
    }
    
    // Start idle timeout monitoring
    security.startIdleTimer();
  });
});

// Functions already moved earlier in the file

// Cleanup on exit
process.on('SIGINT', () => {
  console.log('\nShutdown requested by user...');
  gracefulShutdown();
});