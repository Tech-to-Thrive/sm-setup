/**
 * Base class for platform-specific operations
 * All platform implementations must extend this class
 */
class PlatformBase {
    constructor() {
        this.platform = process.platform;
    }

    /**
     * Run a Docker Compose command
     * @param {string} action - The docker-compose action (up, down, etc.)
     * @param {string} cwd - Working directory
     * @param {Object} options - Additional options
     */
    async runDockerCompose(action, cwd, options = {}) {
        throw new Error('runDockerCompose must be implemented by platform');
    }

    /**
     * Open a firewall port
     * @param {number} port - Port number to open
     * @param {string} protocol - Protocol (tcp/udp)
     */
    async openFirewallPort(port, protocol = 'tcp') {
        throw new Error('openFirewallPort must be implemented by platform');
    }

    /**
     * Check if a command exists
     * @param {string} command - Command to check
     */
    async commandExists(command) {
        throw new Error('commandExists must be implemented by platform');
    }

    /**
     * Get network interfaces
     * @returns {Array} List of network interfaces with IPs
     */
    async getNetworkInterfaces() {
        const os = require('os');
        const interfaces = os.networkInterfaces();
        const result = [];
        
        Object.keys(interfaces).forEach(name => {
            interfaces[name].forEach(iface => {
                if (iface.family === 'IPv4' && !iface.internal) {
                    result.push({
                        name: name,
                        address: iface.address,
                        netmask: iface.netmask
                    });
                }
            });
        });
        
        return result;
    }

    /**
     * Execute a system command
     * @param {string} command - Command to execute
     * @param {Object} options - Execution options
     */
    async executeCommand(command, options = {}) {
        const { exec } = require('child_process');
        const { promisify } = require('util');
        const execAsync = promisify(exec);
        
        try {
            const result = await execAsync(command, {
                maxBuffer: 10 * 1024 * 1024, // 10MB buffer
                ...options
            });
            return {
                success: true,
                stdout: result.stdout,
                stderr: result.stderr
            };
        } catch (error) {
            return {
                success: false,
                error: error.message,
                stdout: error.stdout || '',
                stderr: error.stderr || ''
            };
        }
    }

    /**
     * Check if running with elevated privileges
     */
    async hasElevatedPrivileges() {
        throw new Error('hasElevatedPrivileges must be implemented by platform');
    }

    /**
     * Get Docker command prefix (for WSL2 on Windows)
     */
    getDockerCommand() {
        return 'docker';
    }

    /**
     * Translate paths for the platform (needed for Windows WSL2)
     */
    translatePath(path) {
        return path;
    }

    /**
     * Get platform-specific environment variables
     */
    getEnvironmentVariables() {
        return {};
    }

    /**
     * Check if this is a desktop environment
     */
    isDesktopEnvironment() {
        return false;
    }

    /**
     * Get the shell to use for executing commands
     */
    getShell() {
        return undefined; // Use default
    }

    /**
     * Write a system file with proper permissions
     */
    async writeSystemFile(path, content, options = {}) {
        const fs = require('fs').promises;
        try {
            await fs.writeFile(path, content, options);
            return { success: true };
        } catch (error) {
            return { 
                success: false, 
                error: error.message 
            };
        }
    }

    /**
     * Check port availability
     */
    async isPortAvailable(port) {
        const net = require('net');
        
        return new Promise((resolve) => {
            const server = net.createServer();
            
            server.once('error', (err) => {
                if (err.code === 'EADDRINUSE') {
                    resolve(false);
                } else {
                    resolve(false);
                }
            });
            
            server.once('listening', () => {
                server.close();
                resolve(true);
            });
            
            server.listen(port);
        });
    }

    /**
     * Get platform name for display
     */
    getPlatformName() {
        const osMap = {
            'win32': 'Windows',
            'darwin': 'macOS',
            'linux': 'Linux'
        };
        return osMap[this.platform] || this.platform;
    }
}

module.exports = PlatformBase;