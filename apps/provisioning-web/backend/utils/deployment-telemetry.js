const https = require('https');
const LogAnonymizer = require('./log-anonymizer');

class DeploymentTelemetry {
  constructor(endpoint = 'https://n8n.nsttek.cloud/workflows/sm-event-montoring') {
    this.endpoint = endpoint;
    this.anonymizer = new LogAnonymizer();
  }

  /**
   * Collect comprehensive deployment data
   */
  async collectDeploymentData(executor) {
    const deploymentData = {
      id: executor.deploymentId,
      status: executor.state.status,
      startTime: executor.state.startTime,
      endTime: executor.state.endTime || null,
      duration: executor.state.endTime ? 
        new Date(executor.state.endTime) - new Date(executor.state.startTime) : null,
      
      // Configuration (will be anonymized)
      config: executor.config,
      
      // Steps with full logs
      steps: executor.state.steps,
      
      // System resources
      resources: await this.collectSystemResources(),
      
      // Docker information
      dockerImages: await this.collectDockerImages(),
      
      // Package versions
      packages: await this.collectPackageVersions(),
      
      // Any errors
      errors: this.collectErrors(executor.state.steps),
      
      // Environment info
      environment: {
        nodeVersion: process.version,
        platform: process.platform,
        arch: process.arch,
        projectRoot: process.env.PROJECT_ROOT || 'unknown'
      }
    };

    return deploymentData;
  }

  /**
   * Collect system resource information
   */
  async collectSystemResources() {
    const os = require('os');
    const { execSync } = require('child_process');

    const resources = {
      cpu: {
        model: os.cpus()[0]?.model || 'unknown',
        cores: os.cpus().length,
        loadAverage: os.loadavg()
      },
      memory: {
        total: os.totalmem(),
        free: os.freemem(),
        used: os.totalmem() - os.freemem()
      },
      disk: {}
    };

    // Try to get disk usage
    try {
      const dfOutput = execSync('df -BG / | tail -1').toString();
      const [, size, used, available] = dfOutput.match(/\S+\s+(\d+)G\s+(\d+)G\s+(\d+)G/) || [];
      resources.disk = {
        total: parseInt(size) || 0,
        used: parseInt(used) || 0,
        available: parseInt(available) || 0
      };
    } catch (e) {
      // Disk info collection failed, not critical
    }

    return resources;
  }

  /**
   * Collect Docker images being used
   */
  async collectDockerImages() {
    try {
      const { execSync } = require('child_process');
      const images = execSync('docker images --format "{{.Repository}}:{{.Tag}}"')
        .toString()
        .split('\n')
        .filter(Boolean);
      return images;
    } catch (e) {
      return [];
    }
  }

  /**
   * Collect package versions from package.json files
   */
  async collectPackageVersions() {
    const packages = {};
    const fs = require('fs').promises;
    const path = require('path');

    try {
      // Backend packages
      const backendPkg = await fs.readFile(
        path.join(__dirname, '../package.json'), 
        'utf8'
      );
      packages.backend = JSON.parse(backendPkg).dependencies || {};

      // Frontend packages
      const frontendPkg = await fs.readFile(
        path.join(__dirname, '../../frontend/package.json'), 
        'utf8'
      );
      packages.frontend = JSON.parse(frontendPkg).dependencies || {};
    } catch (e) {
      // Package collection failed, not critical
    }

    return packages;
  }

  /**
   * Extract all errors from deployment steps
   */
  collectErrors(steps) {
    const errors = [];
    
    for (const step of steps) {
      if (step.error) {
        errors.push({
          step: step.id,
          message: step.error.message || step.error,
          timestamp: step.endTime
        });
      }
      
      // Also collect error logs
      if (step.logs) {
        for (const log of step.logs) {
          if (log.level === 'error' || log.type === 'error') {
            errors.push({
              step: step.id,
              message: log.message || log.data || log,
              timestamp: log.timestamp
            });
          }
        }
      }
    }

    return errors;
  }

  /**
   * Send anonymized telemetry to n8n endpoint
   */
  async sendTelemetry(deploymentData) {
    // Generate anonymized report
    const anonymizedReport = this.anonymizer.generateAnonymizedReport(deploymentData);

    // Prepare request data
    const data = JSON.stringify({
      event: 'deployment',
      timestamp: new Date().toISOString(),
      report: anonymizedReport
    });

    // Parse URL
    const url = new URL(this.endpoint);

    const options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
        'User-Agent': 'AI-Stack-Provisioning/1.0'
      }
    };

    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        let responseData = '';

        res.on('data', (chunk) => {
          responseData += chunk;
        });

        res.on('end', () => {
          try {
            const response = JSON.parse(responseData);
            resolve({
              success: res.statusCode >= 200 && res.statusCode < 300,
              statusCode: res.statusCode,
              trackingId: response.uuid || response.trackingId || response.id || null,
              response: response
            });
          } catch (e) {
            resolve({
              success: res.statusCode >= 200 && res.statusCode < 300,
              statusCode: res.statusCode,
              trackingId: null,
              response: responseData
            });
          }
        });
      });

      req.on('error', (error) => {
        console.error('Telemetry send failed:', error);
        reject(error);
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Telemetry request timeout'));
      });

      // Set timeout
      req.setTimeout(30000); // 30 seconds

      req.write(data);
      req.end();
    });
  }

  /**
   * Generate downloadable log files
   */
  async generateDownloadableLogs(deploymentData) {
    const fs = require('fs').promises;
    const path = require('path');
    const os = require('os');

    // Create temp directory for logs
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'deployment-logs-'));

    // Generate full log (original)
    const fullLog = this.generateFullLog(deploymentData);
    const fullLogPath = path.join(tempDir, 'deployment-full.log');
    await fs.writeFile(fullLogPath, fullLog);

    // Generate anonymized log
    const anonymizedLog = this.generateAnonymizedLog(deploymentData);
    const anonymizedLogPath = path.join(tempDir, 'deployment-anonymized.log');
    await fs.writeFile(anonymizedLogPath, anonymizedLog);

    // Generate JSON report (anonymized)
    const jsonReport = this.anonymizer.generateAnonymizedReport(deploymentData);
    const jsonReportPath = path.join(tempDir, 'deployment-report.json');
    await fs.writeFile(jsonReportPath, JSON.stringify(jsonReport, null, 2));

    return {
      tempDir,
      files: {
        full: fullLogPath,
        anonymized: anonymizedLogPath,
        report: jsonReportPath
      }
    };
  }

  /**
   * Generate full text log from deployment data
   */
  generateFullLog(deploymentData) {
    const lines = [];
    
    lines.push('='.repeat(80));
    lines.push('AI STACK DEPLOYMENT LOG');
    lines.push('='.repeat(80));
    lines.push(`Deployment ID: ${deploymentData.id}`);
    lines.push(`Status: ${deploymentData.status}`);
    lines.push(`Start Time: ${deploymentData.startTime || 'N/A'}`);
    lines.push(`End Time: ${deploymentData.endTime || 'N/A'}`);
    lines.push(`Duration: ${deploymentData.duration ? (deploymentData.duration / 1000).toFixed(2) + 's' : 'N/A'}`);
    lines.push('');
    
    lines.push('CONFIGURATION:');
    lines.push('-'.repeat(40));
    lines.push(JSON.stringify(deploymentData.config, null, 2));
    lines.push('');

    lines.push('DEPLOYMENT STEPS:');
    lines.push('-'.repeat(40));
    
    for (const step of deploymentData.steps) {
      lines.push(`\n[STEP ${step.id}] ${step.name}`);
      lines.push(`Status: ${step.status}`);
      if (step.duration) {
        lines.push(`Duration: ${(step.duration / 1000).toFixed(2)}s`);
      }
      
      if (step.logs && step.logs.length > 0) {
        lines.push('Logs:');
        for (const log of step.logs) {
          const timestamp = log.timestamp || '';
          const level = log.level || log.type || 'info';
          const message = log.message || log.data || log;
          lines.push(`  [${timestamp}] [${level}] ${message}`);
        }
      }
      
      if (step.error) {
        lines.push(`ERROR: ${step.error.message || step.error}`);
      }
    }

    lines.push('');
    lines.push('='.repeat(80));
    lines.push('END OF LOG');
    lines.push('='.repeat(80));

    return lines.join('\n');
  }

  /**
   * Generate anonymized text log
   */
  generateAnonymizedLog(deploymentData) {
    const fullLog = this.generateFullLog(deploymentData);
    return this.anonymizer.anonymizeLog(fullLog);
  }
}

module.exports = DeploymentTelemetry;