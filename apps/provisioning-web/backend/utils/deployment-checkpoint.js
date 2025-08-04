const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');

class DeploymentCheckpoint {
  constructor(deploymentId) {
    this.deploymentId = deploymentId;
    this.projectRoot = process.env.PROJECT_ROOT || path.resolve(__dirname, '../../../..');
    this.checkpointDir = path.join(this.projectRoot, '.deployment-checkpoints', deploymentId);
  }

  /**
   * Create a checkpoint after a successful step
   */
  async createCheckpoint(stepIndex, deploymentState, logs) {
    try {
      // Ensure checkpoint directory exists
      await fs.mkdir(this.checkpointDir, { recursive: true });

      const checkpoint = {
        deploymentId: this.deploymentId,
        lastCompletedStep: stepIndex,
        timestamp: new Date().toISOString(),
        config: this.sanitizeConfig(deploymentState.config),
        stepResults: this.extractStepResults(deploymentState.steps),
        logs: logs || [],
        metadata: {
          totalSteps: deploymentState.steps.length,
          deploymentStartTime: deploymentState.startTime,
          checkpointVersion: '1.0'
        }
      };

      // Save checkpoint
      const checkpointPath = path.join(this.checkpointDir, 'checkpoint.json');
      await fs.writeFile(checkpointPath, JSON.stringify(checkpoint, null, 2));

      // Save incremental log file for this step
      if (logs && logs.length > 0) {
        const logPath = path.join(this.checkpointDir, `step-${stepIndex}-logs.json`);
        await fs.writeFile(logPath, JSON.stringify(logs, null, 2));
      }

      return {
        success: true,
        checkpointId: checkpoint.deploymentId,
        lastStep: stepIndex,
        path: checkpointPath
      };
    } catch (error) {
      console.error('Failed to create checkpoint:', error);
      throw error;
    }
  }

  /**
   * Load existing checkpoint for a deployment
   */
  async loadCheckpoint() {
    try {
      const checkpointPath = path.join(this.checkpointDir, 'checkpoint.json');
      
      // Check if checkpoint exists
      try {
        await fs.access(checkpointPath);
      } catch {
        return null; // No checkpoint exists
      }

      const checkpointData = await fs.readFile(checkpointPath, 'utf8');
      const checkpoint = JSON.parse(checkpointData);

      // Validate checkpoint
      if (!this.isValidCheckpoint(checkpoint)) {
        console.warn('Invalid checkpoint found, ignoring');
        return null;
      }

      // Load all step logs
      const consolidatedLogs = await this.loadAllLogs();
      checkpoint.logs = consolidatedLogs;

      return checkpoint;
    } catch (error) {
      console.error('Failed to load checkpoint:', error);
      return null;
    }
  }

  /**
   * Check if a deployment can be resumed
   */
  async canResume() {
    const checkpoint = await this.loadCheckpoint();
    if (!checkpoint) return false;

    // Check if checkpoint is recent (within 24 hours)
    const checkpointAge = Date.now() - new Date(checkpoint.timestamp).getTime();
    const maxAge = 24 * 60 * 60 * 1000; // 24 hours

    if (checkpointAge > maxAge) {
      console.log('Checkpoint too old, cannot resume');
      return false;
    }

    // Check if all required containers still exist for completed steps
    const containersValid = await this.validateContainerStates(checkpoint);
    
    return containersValid;
  }

  /**
   * Resume a deployment from checkpoint
   */
  async resumeDeployment() {
    const checkpoint = await this.loadCheckpoint();
    if (!checkpoint) {
      throw new Error('No checkpoint found to resume from');
    }

    // Validate we can resume
    const canResume = await this.canResume();
    if (!canResume) {
      throw new Error('Cannot resume deployment - checkpoint invalid or expired');
    }

    return {
      resumeFromStep: checkpoint.lastCompletedStep + 1,
      config: checkpoint.config,
      previousLogs: checkpoint.logs,
      stepResults: checkpoint.stepResults,
      metadata: checkpoint.metadata
    };
  }

  /**
   * Delete checkpoint after successful completion or explicit cleanup
   */
  async deleteCheckpoint() {
    try {
      await fs.rm(this.checkpointDir, { recursive: true, force: true });
      return true;
    } catch (error) {
      console.error('Failed to delete checkpoint:', error);
      return false;
    }
  }

  /**
   * List all checkpoints (for debugging/admin)
   */
  static async listAllCheckpoints(projectRoot) {
    const checkpointRoot = path.join(
      projectRoot || process.env.PROJECT_ROOT || '.',
      '.deployment-checkpoints'
    );

    try {
      const deploymentIds = await fs.readdir(checkpointRoot);
      const checkpoints = [];

      for (const deploymentId of deploymentIds) {
        const checkpointPath = path.join(checkpointRoot, deploymentId, 'checkpoint.json');
        try {
          const data = await fs.readFile(checkpointPath, 'utf8');
          const checkpoint = JSON.parse(data);
          checkpoints.push({
            deploymentId,
            lastStep: checkpoint.lastCompletedStep,
            timestamp: checkpoint.timestamp,
            totalSteps: checkpoint.metadata.totalSteps
          });
        } catch (error) {
          // Skip invalid checkpoints
          continue;
        }
      }

      return checkpoints.sort((a, b) => 
        new Date(b.timestamp) - new Date(a.timestamp)
      );
    } catch (error) {
      if (error.code === 'ENOENT') {
        return []; // No checkpoints directory
      }
      throw error;
    }
  }

  /**
   * Clean up old checkpoints (retention policy)
   */
  static async cleanupOldCheckpoints(projectRoot, maxAgeDays = 7) {
    const checkpoints = await DeploymentCheckpoint.listAllCheckpoints(projectRoot);
    const maxAge = maxAgeDays * 24 * 60 * 60 * 1000;
    const now = Date.now();
    let cleaned = 0;

    for (const checkpoint of checkpoints) {
      const age = now - new Date(checkpoint.timestamp).getTime();
      if (age > maxAge) {
        const cp = new DeploymentCheckpoint(checkpoint.deploymentId);
        if (await cp.deleteCheckpoint()) {
          cleaned++;
        }
      }
    }

    return cleaned;
  }

  // Private helper methods

  sanitizeConfig(config) {
    if (!config) return {};
    
    const sanitized = { ...config };
    // Redact sensitive information
    if (sanitized.adminPassword) sanitized.adminPassword = '[REDACTED]';
    if (sanitized.webhookSecret) sanitized.webhookSecret = '[REDACTED]';
    if (sanitized.cloudflareApiKey) sanitized.cloudflareApiKey = '[REDACTED]';
    if (sanitized.encryptionKey) sanitized.encryptionKey = '[REDACTED]';
    
    return sanitized;
  }

  extractStepResults(steps) {
    const results = {};
    steps.forEach((step, index) => {
      if (step.status === 'completed') {
        results[index] = {
          status: step.status,
          duration: step.duration,
          startTime: step.startTime,
          endTime: step.endTime
        };
      }
    });
    return results;
  }

  async loadAllLogs() {
    const logs = [];
    try {
      const files = await fs.readdir(this.checkpointDir);
      const logFiles = files.filter(f => f.match(/^step-\d+-logs\.json$/));
      
      // Sort by step number
      logFiles.sort((a, b) => {
        const stepA = parseInt(a.match(/step-(\d+)/)[1]);
        const stepB = parseInt(b.match(/step-(\d+)/)[1]);
        return stepA - stepB;
      });

      for (const logFile of logFiles) {
        const logPath = path.join(this.checkpointDir, logFile);
        const logData = await fs.readFile(logPath, 'utf8');
        const stepLogs = JSON.parse(logData);
        logs.push(...stepLogs);
      }
    } catch (error) {
      console.error('Error loading logs:', error);
    }
    return logs;
  }

  isValidCheckpoint(checkpoint) {
    return checkpoint &&
           checkpoint.deploymentId === this.deploymentId &&
           typeof checkpoint.lastCompletedStep === 'number' &&
           checkpoint.timestamp &&
           checkpoint.config &&
           checkpoint.stepResults;
  }

  async validateContainerStates(checkpoint) {
    // This would check if containers from completed steps still exist
    // For now, we'll assume they're valid if the checkpoint is recent
    // In a full implementation, we'd use Docker API to verify
    return true;
  }
}

module.exports = DeploymentCheckpoint;