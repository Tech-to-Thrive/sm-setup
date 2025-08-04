const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const os = require('os');
const net = require('net');
const { safeExecute } = require('./safe-execute');

/**
 * Resource validation utilities for pre-deployment checks
 * Ensures sufficient resources are available before starting deployment
 */
class ResourceValidator {
  /**
   * Check available disk space
   * @param {number} requiredGB - Required space in GB (default 10)
   * @returns {object} - Space check results
   */
  static async checkDiskSpace(requiredGB = 10) {
    try {
      // Check Docker directory space
      const dockerDir = '/var/lib/docker';
      
      // Use df to check disk space
      const { stdout } = await safeExecute('df', ['-BG', dockerDir]);
      const lines = stdout.split('\n').filter(line => line.trim());
      
      // Parse df output - find line containing docker dir or its mount point
      let dockerLine = lines.find(line => line.includes(dockerDir));
      if (!dockerLine && lines.length > 1) {
        // If docker dir not found, use the last line (usually the mount point)
        dockerLine = lines[lines.length - 1];
      }
      
      if (!dockerLine) {
        throw new Error('Could not determine disk space');
      }
      
      // Parse available space (4th column in df output)
      const parts = dockerLine.split(/\s+/);
      const availableStr = parts[3] || '0G';
      const availableGB = parseInt(availableStr.replace('G', ''));
      
      return {
        location: dockerDir,
        available: availableGB,
        required: requiredGB,
        sufficient: availableGB >= requiredGB,
        message: availableGB < requiredGB 
          ? `Insufficient disk space. Need ${requiredGB}GB, have ${availableGB}GB available`
          : `Disk space OK: ${availableGB}GB available (need ${requiredGB}GB)`
      };
    } catch (error) {
      return {
        location: '/var/lib/docker',
        available: 0,
        required: requiredGB,
        sufficient: false,
        message: `Failed to check disk space: ${error.message}`,
        error: error.message
      };
    }
  }

  /**
   * Check available memory
   * @param {number} requiredGB - Required memory in GB (default 4)
   * @returns {object} - Memory check results
   */
  static async checkMemory(requiredGB = 4) {
    try {
      // Read memory info from /proc/meminfo
      const meminfo = await fsPromises.readFile('/proc/meminfo', 'utf8');
      
      // Parse total and available memory
      const totalMatch = meminfo.match(/MemTotal:\s+(\d+)\s+kB/);
      const availableMatch = meminfo.match(/MemAvailable:\s+(\d+)\s+kB/);
      
      if (!totalMatch || !availableMatch) {
        throw new Error('Could not parse memory information');
      }
      
      const totalKB = parseInt(totalMatch[1]);
      const availableKB = parseInt(availableMatch[1]);
      
      // Convert to GB
      const totalGB = Math.floor(totalKB / 1024 / 1024);
      const availableGB = Math.floor(availableKB / 1024 / 1024);
      
      return {
        total: totalGB,
        available: availableGB,
        required: requiredGB,
        sufficient: availableGB >= requiredGB,
        message: availableGB < requiredGB
          ? `Insufficient memory. Need ${requiredGB}GB, have ${availableGB}GB available`
          : `Memory OK: ${availableGB}GB available of ${totalGB}GB total (need ${requiredGB}GB)`
      };
    } catch (error) {
      return {
        total: 0,
        available: 0,
        required: requiredGB,
        sufficient: false,
        message: `Failed to check memory: ${error.message}`,
        error: error.message
      };
    }
  }

  /**
   * Check if Docker is running and accessible
   * @returns {object} - Docker check results
   */
  static async checkDocker() {
    try {
      // Check if docker command exists
      await safeExecute('which', ['docker']);
      
      // Check if Docker daemon is running
      const { stdout } = await safeExecute('docker', ['info', '--format', 'json']);
      const dockerInfo = JSON.parse(stdout);
      
      // Check Docker version
      const { stdout: versionOut } = await safeExecute('docker', ['version', '--format', 'json']);
      const versionInfo = JSON.parse(versionOut);
      
      return {
        available: true,
        running: true,
        version: versionInfo.Client?.Version || 'unknown',
        serverVersion: dockerInfo.ServerVersion || 'unknown',
        message: `Docker OK: ${dockerInfo.ServerVersion || 'version unknown'}`,
        info: {
          containers: dockerInfo.Containers || 0,
          images: dockerInfo.Images || 0,
          driver: dockerInfo.Driver || 'unknown'
        }
      };
    } catch (error) {
      // Try to determine the specific issue
      let message = 'Docker is not available';
      let details = error.message;
      
      if (error.message.includes('which: no docker')) {
        message = 'Docker is not installed';
      } else if (error.message.includes('Cannot connect to the Docker daemon')) {
        message = 'Docker daemon is not running';
        details = 'Start Docker with: sudo systemctl start docker';
      } else if (error.message.includes('permission denied')) {
        message = 'Docker requires elevated permissions';
        details = 'Add user to docker group or use sudo';
      }
      
      return {
        available: false,
        running: false,
        message,
        error: details
      };
    }
  }

  /**
   * Check network connectivity to required endpoints
   * @returns {object} - Network check results
   */
  static async checkNetwork() {
    const endpoints = [
      { host: 'hub.docker.com', port: 443, name: 'Docker Hub', critical: true },
      { host: 'registry-1.docker.io', port: 443, name: 'Docker Registry', critical: true },
      { host: 'github.com', port: 443, name: 'GitHub', critical: false },
      { host: 'production.cloudflare.docker.com', port: 443, name: 'Docker CDN', critical: false }
    ];
    
    const results = await Promise.all(
      endpoints.map(endpoint => this.checkEndpoint(endpoint))
    );
    
    const failed = results.filter(r => !r.accessible);
    const criticalFailed = failed.filter(r => r.critical);
    
    return {
      allAccessible: failed.length === 0,
      criticalAccessible: criticalFailed.length === 0,
      results,
      summary: {
        total: endpoints.length,
        accessible: results.filter(r => r.accessible).length,
        failed: failed.length,
        criticalFailed: criticalFailed.length
      },
      message: criticalFailed.length > 0
        ? `Critical endpoints unreachable: ${criticalFailed.map(f => f.name).join(', ')}`
        : failed.length > 0
          ? `Some endpoints unreachable: ${failed.map(f => f.name).join(', ')}`
          : 'All network endpoints accessible'
    };
  }

  /**
   * Check a single network endpoint
   * @param {object} endpoint - Endpoint to check
   * @returns {object} - Endpoint check result
   */
  static async checkEndpoint(endpoint) {
    return new Promise((resolve) => {
      const socket = new net.Socket();
      const timeout = 5000; // 5 second timeout
      
      const result = {
        ...endpoint,
        accessible: false,
        latency: null,
        error: null
      };
      
      const startTime = Date.now();
      
      socket.setTimeout(timeout);
      
      socket.on('connect', () => {
        result.accessible = true;
        result.latency = Date.now() - startTime;
        socket.destroy();
        resolve(result);
      });
      
      socket.on('timeout', () => {
        result.error = 'Connection timeout';
        socket.destroy();
        resolve(result);
      });
      
      socket.on('error', (err) => {
        result.error = err.message;
        resolve(result);
      });
      
      socket.connect(endpoint.port, endpoint.host);
    });
  }

  /**
   * Check if required ports are available
   * @returns {object} - Port check results
   */
  static async checkPorts() {
    const requiredPorts = [
      { port: 3000, service: 'Grafana' },
      { port: 3001, service: 'Stack Manager UI' },
      { port: 3002, service: 'Stack Manager API' },
      { port: 5678, service: 'n8n' },
      { port: 9090, service: 'Prometheus' },
      { port: 9999, service: 'GoTrue Auth' },
      { port: 5433, service: 'PostgreSQL' },
      { port: 3100, service: 'Loki' }
    ];
    
    const conflicts = [];
    
    for (const { port, service } of requiredPorts) {
      const inUse = await this.isPortInUse(port);
      if (inUse) {
        conflicts.push({ port, service });
      }
    }
    
    return {
      available: conflicts.length === 0,
      conflicts,
      message: conflicts.length > 0
        ? `Ports in use: ${conflicts.map(c => `${c.port} (${c.service})`).join(', ')}`
        : 'All required ports available'
    };
  }

  /**
   * Check if a port is in use
   * @param {number} port - Port to check
   * @returns {boolean} - True if port is in use
   */
  static async isPortInUse(port) {
    return new Promise((resolve) => {
      const server = net.createServer();
      
      server.once('error', (err) => {
        if (err.code === 'EADDRINUSE') {
          resolve(true);
        } else {
          resolve(false);
        }
      });
      
      server.once('listening', () => {
        server.close();
        resolve(false);
      });
      
      server.listen(port, '127.0.0.1');
    });
  }

  /**
   * Run all pre-flight checks
   * @returns {object} - Combined results of all checks
   */
  static async runPreflightChecks() {
    const startTime = Date.now();
    
    // Run all checks in parallel
    const [disk, memory, docker, network, ports] = await Promise.all([
      this.checkDiskSpace(),
      this.checkMemory(),
      this.checkDocker(),
      this.checkNetwork(),
      this.checkPorts()
    ]);
    
    const duration = Date.now() - startTime;
    
    // Determine overall status
    const criticalIssues = [];
    const warnings = [];
    
    if (!disk.sufficient) criticalIssues.push(disk.message);
    if (!memory.sufficient) criticalIssues.push(memory.message);
    if (!docker.available) criticalIssues.push(docker.message);
    if (!network.criticalAccessible) criticalIssues.push(network.message);
    if (!ports.available) warnings.push(ports.message);
    
    const passed = criticalIssues.length === 0;
    
    return {
      passed,
      duration,
      timestamp: new Date().toISOString(),
      checks: {
        disk,
        memory,
        docker,
        network,
        ports
      },
      summary: {
        criticalIssues,
        warnings,
        message: passed
          ? warnings.length > 0
            ? `Pre-flight checks passed with warnings: ${warnings.join('; ')}`
            : 'All pre-flight checks passed'
          : `Pre-flight checks failed: ${criticalIssues.join('; ')}`
      }
    };
  }
}

module.exports = ResourceValidator;