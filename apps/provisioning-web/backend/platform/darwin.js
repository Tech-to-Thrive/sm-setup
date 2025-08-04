const PlatformBase = require('./base');

/**
 * macOS (Darwin) platform-specific operations
 */
class DarwinPlatform extends PlatformBase {
    constructor() {
        super();
    }

    async runDockerCompose(action, cwd, options = {}) {
        // macOS Docker Desktop typically has docker compose v2
        const command = `docker compose ${action}`;
        
        let result = await this.executeCommand(command, { cwd, ...options });
        
        // Fallback to docker-compose if v2 fails
        if (!result.success) {
            result = await this.executeCommand(`docker-compose ${action}`, { cwd, ...options });
        }
        
        return result;
    }

    async openFirewallPort(port, protocol = 'tcp') {
        // macOS uses pfctl for firewall management
        // However, most macOS systems don't have firewall enabled by default
        
        // Check if firewall is enabled
        const fwCheckResult = await this.executeCommand(
            'sudo pfctl -s info 2>/dev/null | grep "Status: Enabled"'
        );
        
        if (!fwCheckResult.success || !fwCheckResult.stdout) {
            return {
                success: true,
                message: 'macOS firewall is not enabled, port is accessible'
            };
        }
        
        // If firewall is enabled, add rule
        // Note: This is complex on macOS and usually requires modifying /etc/pf.conf
        // For simplicity, we'll return instructions
        return {
            success: false,
            message: `To open port ${port} on macOS:
1. Edit /etc/pf.conf as root
2. Add: pass in proto ${protocol} from any to any port ${port}
3. Reload with: sudo pfctl -f /etc/pf.conf
4. Or disable firewall in System Preferences > Security & Privacy > Firewall`
        };
    }

    async commandExists(command) {
        const result = await this.executeCommand(`which ${command}`);
        return result.success && result.stdout.trim() !== '';
    }

    async hasElevatedPrivileges() {
        const result = await this.executeCommand('id -u');
        return result.success && result.stdout.trim() === '0';
    }

    isDesktopEnvironment() {
        // macOS is always a desktop environment
        return true;
    }

    async getSystemInfo() {
        const info = {};
        
        // Get macOS version
        const versionResult = await this.executeCommand('sw_vers');
        if (versionResult.success) {
            const lines = versionResult.stdout.split('\n');
            lines.forEach(line => {
                const [key, value] = line.split(':').map(s => s.trim());
                if (key && value) {
                    info[key.toLowerCase().replace(/\s+/g, '_')] = value;
                }
            });
        }
        
        // Get hardware info
        const hwResult = await this.executeCommand('sysctl -n hw.model');
        if (hwResult.success) {
            info.hardware = hwResult.stdout.trim();
        }
        
        // Check if Apple Silicon
        const archResult = await this.executeCommand('uname -m');
        if (archResult.success) {
            info.architecture = archResult.stdout.trim();
            info.isAppleSilicon = info.architecture === 'arm64';
        }
        
        return info;
    }

    async checkDockerPermissions() {
        // On macOS, Docker Desktop runs as the current user
        const result = await this.executeCommand('docker ps', { timeout: 5000 });
        
        if (!result.success) {
            if (result.stderr.includes('Cannot connect to the Docker daemon')) {
                return {
                    hasPermission: false,
                    suggestion: 'Docker Desktop is not running. Please start Docker Desktop from Applications.'
                };
            }
            return {
                hasPermission: false,
                suggestion: 'Cannot connect to Docker. Ensure Docker Desktop is installed and running.'
            };
        }
        
        return { hasPermission: true };
    }

    async getDockerInfo() {
        const info = {};
        
        // Check Docker version
        const versionResult = await this.executeCommand('docker --version');
        if (versionResult.success) {
            info.version = versionResult.stdout.trim();
        }
        
        // Check if Docker daemon is running
        const infoResult = await this.executeCommand('docker info --format json');
        if (infoResult.success) {
            try {
                const dockerInfo = JSON.parse(infoResult.stdout);
                info.running = true;
                info.serverVersion = dockerInfo.ServerVersion;
                info.storageDriver = dockerInfo.Driver;
                info.dockerRootDir = dockerInfo.DockerRootDir;
                
                // Check if running with Rosetta on Apple Silicon
                if (dockerInfo.Architecture === 'x86_64') {
                    const sysInfo = await this.getSystemInfo();
                    if (sysInfo.isAppleSilicon) {
                        info.rosettaMode = true;
                    }
                }
            } catch (e) {
                info.running = false;
            }
        } else {
            info.running = false;
        }
        
        return info;
    }

    async installNodeJs() {
        // Check for Homebrew first (most common on macOS)
        if (await this.commandExists('brew')) {
            return this.executeCommand('brew install node');
        }
        
        // Check for MacPorts
        if (await this.commandExists('port')) {
            return this.executeCommand('sudo port install nodejs18 +universal');
        }
        
        // Direct download from nodejs.org
        return {
            success: false,
            error: 'Please install Node.js from https://nodejs.org/ or install Homebrew first: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        };
    }

    getEnvironmentVariables() {
        return {
            // Always use localhost on macOS desktop
            HOST: 'localhost',
            // Ensure proper file watching on macOS
            CHOKIDAR_USEPOLLING: 'false'
        };
    }

    async checkGatekeeper(appPath) {
        // Check if app will be blocked by Gatekeeper
        const result = await this.executeCommand(`spctl -a -v ${appPath}`);
        
        if (!result.success && result.stderr.includes('rejected')) {
            return {
                allowed: false,
                suggestion: `To allow this app: sudo spctl --add ${appPath}`
            };
        }
        
        return { allowed: true };
    }

    async requestPermissions() {
        // macOS may require permissions for certain operations
        const permissions = [];
        
        // Check if Terminal/IDE has full disk access
        const fdaCheck = await this.executeCommand(
            'sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db "SELECT * FROM access WHERE service=\'kTCCServiceSystemPolicyAllFiles\'"'
        );
        
        if (!fdaCheck.success) {
            permissions.push({
                type: 'Full Disk Access',
                required: false,
                instruction: 'Grant Full Disk Access to Terminal in System Preferences > Security & Privacy > Privacy'
            });
        }
        
        return permissions;
    }
}

module.exports = DarwinPlatform;