const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const { safeExecute } = require('./safe-execute');

/**
 * Deployment Snapshot Manager
 * Captures and restores deployment state for rollback functionality
 */
class DeploymentSnapshot {
  constructor(deploymentId) {
    this.deploymentId = deploymentId;
    this.snapshotDir = path.join(process.cwd(), '.deployment-snapshots', deploymentId);
  }

  /**
   * Initialize snapshot directory
   */
  async init() {
    await fsPromises.mkdir(this.snapshotDir, { recursive: true });
  }

  /**
   * Create a snapshot of current deployment state
   * @param {number} step - Current deployment step
   * @param {object} config - Deployment configuration
   * @returns {object} Snapshot metadata
   */
  async createSnapshot(step, config) {
    await this.init();
    
    const timestamp = new Date().toISOString();
    const snapshotId = `step-${step}-${Date.now()}`;
    
    const snapshot = {
      id: snapshotId,
      deploymentId: this.deploymentId,
      step,
      timestamp,
      config: this.sanitizeConfig(config),
      state: {
        containers: await this.captureContainerState(),
        volumes: await this.captureVolumeState(),
        networks: await this.captureNetworkState(),
        envFile: await this.captureEnvFile(),
        services: await this.captureServiceStates()
      }
    };

    // Save snapshot metadata
    const snapshotPath = path.join(this.snapshotDir, `${snapshotId}.json`);
    await fsPromises.writeFile(
      snapshotPath, 
      JSON.stringify(snapshot, null, 2)
    );

    // Save env file backup
    if (snapshot.state.envFile.content) {
      const envBackupPath = path.join(this.snapshotDir, `${snapshotId}.env`);
      await fsPromises.writeFile(envBackupPath, snapshot.state.envFile.content);
    }

    return {
      id: snapshotId,
      path: snapshotPath,
      timestamp,
      step
    };
  }

  /**
   * List available snapshots for this deployment
   * @returns {array} List of snapshot metadata
   */
  async listSnapshots() {
    try {
      const files = await fsPromises.readdir(this.snapshotDir);
      const snapshots = [];
      
      for (const file of files) {
        if (file.endsWith('.json')) {
          const content = await fsPromises.readFile(
            path.join(this.snapshotDir, file), 
            'utf8'
          );
          const snapshot = JSON.parse(content);
          snapshots.push({
            id: snapshot.id,
            step: snapshot.step,
            timestamp: snapshot.timestamp,
            file
          });
        }
      }
      
      // Sort by step number descending
      return snapshots.sort((a, b) => b.step - a.step);
    } catch (error) {
      if (error.code === 'ENOENT') {
        return [];
      }
      throw error;
    }
  }

  /**
   * Rollback to a specific snapshot
   * @param {string} snapshotId - Snapshot ID to rollback to
   * @returns {object} Rollback result
   */
  async rollback(snapshotId) {
    const snapshotPath = path.join(this.snapshotDir, `${snapshotId}.json`);
    
    // Load snapshot
    const snapshotContent = await fsPromises.readFile(snapshotPath, 'utf8');
    const snapshot = JSON.parse(snapshotContent);
    
    const rollbackSteps = [];
    const errors = [];
    
    try {
      // Step 1: Stop current containers
      rollbackSteps.push({ step: 'stop-containers', status: 'starting' });
      await this.stopAllContainers();
      rollbackSteps[rollbackSteps.length - 1].status = 'completed';
      
      // Step 2: Restore environment file
      if (snapshot.state.envFile.content) {
        rollbackSteps.push({ step: 'restore-env', status: 'starting' });
        await this.restoreEnvFile(snapshot.state.envFile);
        rollbackSteps[rollbackSteps.length - 1].status = 'completed';
      }
      
      // Step 3: Remove containers not in snapshot
      rollbackSteps.push({ step: 'cleanup-containers', status: 'starting' });
      await this.cleanupContainers(snapshot.state.containers);
      rollbackSteps[rollbackSteps.length - 1].status = 'completed';
      
      // Step 4: Restore container states
      rollbackSteps.push({ step: 'restore-containers', status: 'starting' });
      await this.restoreContainers(snapshot.state.containers);
      rollbackSteps[rollbackSteps.length - 1].status = 'completed';
      
      // Step 5: Verify services
      rollbackSteps.push({ step: 'verify-services', status: 'starting' });
      await this.verifyServices(snapshot.state.services);
      rollbackSteps[rollbackSteps.length - 1].status = 'completed';
      
      return {
        success: true,
        snapshot,
        steps: rollbackSteps,
        message: `Successfully rolled back to step ${snapshot.step}`
      };
      
    } catch (error) {
      errors.push(error.message);
      return {
        success: false,
        snapshot,
        steps: rollbackSteps,
        errors,
        message: `Rollback failed: ${error.message}`
      };
    }
  }

  /**
   * Capture current container state
   */
  async captureContainerState() {
    try {
      const { stdout } = await safeExecute('docker', [
        'ps', '-a', '--format', 'json',
        '--filter', 'label=com.docker.compose.project=n8n-monitoring'
      ]);
      
      const containers = stdout
        .trim()
        .split('\n')
        .filter(line => line)
        .map(line => JSON.parse(line));
      
      return containers.map(c => ({
        id: c.ID,
        name: c.Names,
        image: c.Image,
        state: c.State,
        status: c.Status,
        labels: c.Labels,
        created: c.CreatedAt
      }));
    } catch (error) {
      console.error('Failed to capture container state:', error);
      return [];
    }
  }

  /**
   * Capture volume state
   */
  async captureVolumeState() {
    try {
      const { stdout } = await safeExecute('docker', [
        'volume', 'ls', '--format', 'json',
        '--filter', 'label=com.docker.compose.project=n8n-monitoring'
      ]);
      
      const volumes = stdout
        .trim()
        .split('\n')
        .filter(line => line)
        .map(line => JSON.parse(line));
      
      return volumes.map(v => ({
        name: v.Name,
        driver: v.Driver,
        labels: v.Labels
      }));
    } catch (error) {
      console.error('Failed to capture volume state:', error);
      return [];
    }
  }

  /**
   * Capture network state
   */
  async captureNetworkState() {
    try {
      const { stdout } = await safeExecute('docker', [
        'network', 'ls', '--format', 'json',
        '--filter', 'label=com.docker.compose.project=n8n-monitoring'
      ]);
      
      const networks = stdout
        .trim()
        .split('\n')
        .filter(line => line)
        .map(line => JSON.parse(line));
      
      return networks.map(n => ({
        id: n.ID,
        name: n.Name,
        driver: n.Driver,
        scope: n.Scope
      }));
    } catch (error) {
      console.error('Failed to capture network state:', error);
      return [];
    }
  }

  /**
   * Capture environment file
   */
  async captureEnvFile() {
    const envPath = path.join(process.env.PROJECT_ROOT || process.cwd(), 'deploy/docker/.env');
    
    try {
      const content = await fsPromises.readFile(envPath, 'utf8');
      const checksum = crypto.createHash('sha256').update(content).digest('hex');
      
      return {
        path: envPath,
        content,
        checksum,
        size: content.length
      };
    } catch (error) {
      console.error('Failed to capture env file:', error);
      return {
        path: envPath,
        content: null,
        error: error.message
      };
    }
  }

  /**
   * Capture service states (health, ports, etc)
   */
  async captureServiceStates() {
    const services = {
      'stack-manager': { port: 3001, health: null },
      'n8n': { port: 5678, health: null },
      'grafana': { port: 3000, health: null },
      'prometheus': { port: 9090, health: null }
    };
    
    // Check each service health
    for (const [name, service] of Object.entries(services)) {
      try {
        const { stdout } = await safeExecute('docker', [
          'ps', '--format', 'json',
          '--filter', `name=${name}`
        ]);
        
        if (stdout.trim()) {
          const container = JSON.parse(stdout.trim().split('\n')[0]);
          service.health = container.State === 'running' ? 'healthy' : 'unhealthy';
          service.status = container.Status;
        }
      } catch (error) {
        service.health = 'unknown';
        service.error = error.message;
      }
    }
    
    return services;
  }

  /**
   * Stop all containers
   */
  async stopAllContainers() {
    try {
      await safeExecute('docker', [
        'compose', '-f', 
        path.join(process.env.PROJECT_ROOT || process.cwd(), 'docker-compose.yml'),
        'stop'
      ]);
    } catch (error) {
      console.error('Error stopping containers:', error);
      // Continue with rollback even if stop fails
    }
  }

  /**
   * Restore environment file from snapshot
   */
  async restoreEnvFile(envSnapshot) {
    if (!envSnapshot.content) {
      throw new Error('No environment file content in snapshot');
    }
    
    // Backup current env file
    const currentEnvPath = envSnapshot.path;
    const backupPath = `${currentEnvPath}.rollback-backup-${Date.now()}`;
    
    try {
      await fsPromises.copyFile(currentEnvPath, backupPath);
    } catch (error) {
      console.warn('Could not backup current env file:', error);
    }
    
    // Restore env file
    await fsPromises.writeFile(currentEnvPath, envSnapshot.content);
  }

  /**
   * Remove containers not present in snapshot
   */
  async cleanupContainers(snapshotContainers) {
    const currentContainers = await this.captureContainerState();
    const snapshotNames = new Set(snapshotContainers.map(c => c.name));
    
    for (const container of currentContainers) {
      if (!snapshotNames.has(container.name)) {
        try {
          await safeExecute('docker', ['rm', '-f', container.id]);
        } catch (error) {
          console.warn(`Could not remove container ${container.name}:`, error);
        }
      }
    }
  }

  /**
   * Restore containers to snapshot state
   */
  async restoreContainers(snapshotContainers) {
    // Start containers using docker-compose
    try {
      await safeExecute('docker', [
        'compose', '-f',
        path.join(process.env.PROJECT_ROOT || process.cwd(), 'docker-compose.yml'),
        'up', '-d'
      ]);
      
      // Wait for containers to be ready
      await new Promise(resolve => setTimeout(resolve, 5000));
    } catch (error) {
      throw new Error(`Failed to restore containers: ${error.message}`);
    }
  }

  /**
   * Verify services are running
   */
  async verifyServices(snapshotServices) {
    const errors = [];
    
    for (const [name, expectedState] of Object.entries(snapshotServices)) {
      if (expectedState.health === 'healthy') {
        try {
          const { stdout } = await safeExecute('docker', [
            'ps', '--format', '{{.State}}',
            '--filter', `name=${name}`
          ]);
          
          if (!stdout.includes('running')) {
            errors.push(`Service ${name} is not running`);
          }
        } catch (error) {
          errors.push(`Could not verify service ${name}: ${error.message}`);
        }
      }
    }
    
    if (errors.length > 0) {
      console.warn('Service verification warnings:', errors);
    }
  }

  /**
   * Sanitize config to remove sensitive data
   */
  sanitizeConfig(config) {
    const sanitized = { ...config };
    
    // Remove sensitive fields
    const sensitiveFields = [
      'adminPassword', 'postgresPassword', 'redisPassword',
      'jwtSecret', 'anonKey', 'serviceKey', 'cloudflareToken'
    ];
    
    for (const field of sensitiveFields) {
      if (sanitized[field]) {
        sanitized[field] = '[REDACTED]';
      }
    }
    
    return sanitized;
  }

  /**
   * Delete old snapshots (keep last N)
   */
  async cleanup(keepCount = 5) {
    const snapshots = await this.listSnapshots();
    
    if (snapshots.length <= keepCount) {
      return;
    }
    
    // Delete oldest snapshots
    const toDelete = snapshots.slice(keepCount);
    
    for (const snapshot of toDelete) {
      try {
        await fsPromises.unlink(path.join(this.snapshotDir, snapshot.file));
        
        // Also delete env backup if exists
        const envFile = snapshot.file.replace('.json', '.env');
        await fsPromises.unlink(path.join(this.snapshotDir, envFile)).catch(() => {});
      } catch (error) {
        console.warn(`Could not delete snapshot ${snapshot.id}:`, error);
      }
    }
  }
}

module.exports = DeploymentSnapshot;