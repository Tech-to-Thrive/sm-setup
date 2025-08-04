const lockfile = require('proper-lockfile');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const os = require('os');

/**
 * Deployment lock manager to prevent concurrent deployments
 * Uses file-based locking with stale detection
 */
class DeploymentLock {
  constructor() {
    // Use a system-wide lock file location
    this.lockDir = path.join(os.tmpdir(), 'ai-stack-provisioning');
    this.lockPath = path.join(this.lockDir, 'deployment.lock');
    this.pidPath = path.join(this.lockDir, 'deployment.pid');
    this.release = null;
  }

  /**
   * Initialize lock directory
   */
  async init() {
    try {
      await fsPromises.mkdir(this.lockDir, { recursive: true, mode: 0o755 });
    } catch (error) {
      console.error('Failed to create lock directory:', error);
    }
  }

  /**
   * Acquire deployment lock
   * @returns {boolean} True if lock acquired, false if another deployment is running
   */
  async acquire() {
    await this.init();

    try {
      // First check if another deployment is running
      const isLocked = await this.isLocked();
      if (isLocked) {
        const runningPid = await this.getRunningPid();
        console.log(`Another deployment is running (PID: ${runningPid})`);
        return false;
      }

      // Create lock file if it doesn't exist
      if (!fs.existsSync(this.lockPath)) {
        await fsPromises.writeFile(this.lockPath, '', { flag: 'wx' });
      }

      // Try to acquire lock
      this.release = await lockfile.lock(this.lockPath, {
        stale: 60000, // Consider lock stale after 60 seconds
        retries: {
          retries: 0, // Don't retry, fail immediately
          minTimeout: 0
        },
        realpath: false // Don't follow symlinks
      });

      // Write our PID
      await fsPromises.writeFile(this.pidPath, process.pid.toString(), { mode: 0o644 });
      
      console.log(`Deployment lock acquired (PID: ${process.pid})`);
      return true;

    } catch (error) {
      if (error.code === 'ELOCKED') {
        // Lock is held by another process
        const runningPid = await this.getRunningPid();
        console.log(`Deployment already in progress (PID: ${runningPid})`);
        return false;
      }
      
      // For other errors, check if the process is stale
      if (error.code === 'ENOENT' || error.code === 'EPERM') {
        // Lock file was removed or we don't have permission
        // Try to clean up and retry once
        await this.cleanup();
        return this.acquire();
      }

      console.error('Failed to acquire deployment lock:', error);
      throw error;
    }
  }

  /**
   * Release deployment lock
   */
  async release() {
    if (this.release) {
      try {
        await this.release();
        console.log('Deployment lock released');
      } catch (error) {
        console.error('Failed to release lock:', error);
      }
      this.release = null;
    }

    // Clean up PID file
    try {
      await fsPromises.unlink(this.pidPath);
    } catch (error) {
      // Ignore if file doesn't exist
    }
  }

  /**
   * Check if deployment is currently locked
   */
  async isLocked() {
    try {
      // Check if lock file exists
      if (!fs.existsSync(this.lockPath)) {
        return false;
      }

      // Check if it's actually locked
      const locked = await lockfile.check(this.lockPath, {
        stale: 60000,
        realpath: false
      });

      if (locked) {
        // Verify the process is actually running
        const pid = await this.getRunningPid();
        if (pid && this.isProcessRunning(pid)) {
          return true;
        } else {
          // Process is dead, clean up stale lock
          console.log('Cleaning up stale deployment lock');
          await this.forceUnlock();
          return false;
        }
      }

      return false;
    } catch (error) {
      console.error('Error checking lock status:', error);
      return false;
    }
  }

  /**
   * Get PID of running deployment
   */
  async getRunningPid() {
    try {
      const pidStr = await fsPromises.readFile(this.pidPath, 'utf8');
      return parseInt(pidStr.trim());
    } catch (error) {
      return null;
    }
  }

  /**
   * Check if a process is running
   */
  isProcessRunning(pid) {
    try {
      // Send signal 0 to check if process exists
      process.kill(pid, 0);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Force unlock (use with caution)
   */
  async forceUnlock() {
    try {
      await lockfile.unlock(this.lockPath, { realpath: false });
    } catch (error) {
      // Ignore errors
    }

    // Clean up files
    await this.cleanup();
  }

  /**
   * Clean up lock files
   */
  async cleanup() {
    try {
      await fsPromises.unlink(this.lockPath);
    } catch (error) {
      // Ignore if doesn't exist
    }

    try {
      await fsPromises.unlink(this.pidPath);
    } catch (error) {
      // Ignore if doesn't exist
    }
  }

  /**
   * Get lock status information
   */
  async getStatus() {
    const locked = await this.isLocked();
    const pid = await this.getRunningPid();
    
    let lockAge = null;
    try {
      const stats = await fsPromises.stat(this.lockPath);
      lockAge = Date.now() - stats.mtimeMs;
    } catch (error) {
      // Ignore
    }

    return {
      locked,
      pid,
      lockAge,
      stale: lockAge > 60000
    };
  }
}

// Handle process termination
process.on('exit', async () => {
  // Try to clean up lock on exit
  const lock = new DeploymentLock();
  await lock.cleanup();
});

module.exports = DeploymentLock;