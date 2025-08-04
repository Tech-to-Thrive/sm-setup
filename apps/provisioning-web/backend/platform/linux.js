const PlatformBase = require('./base');

/**
 * Linux platform-specific operations
 */
class LinuxPlatform extends PlatformBase {
    constructor() {
        super();
    }

    async runDockerCompose(action, cwd, options = {}) {
        // Check for docker compose v2 first, fallback to v1
        const dockerComposeV2 = await this.commandExists('docker compose');
        const command = dockerComposeV2 
            ? `docker compose ${action}` 
            : `docker-compose ${action}`;
        
        return this.executeCommand(command, { cwd, ...options });
    }

    async openFirewallPort(port, protocol = 'tcp') {
        // Try different firewall managers in order of preference
        
        // UFW (Ubuntu/Debian)
        if (await this.commandExists('ufw')) {
            const result = await this.executeCommand(`sudo ufw allow ${port}/${protocol}`);
            if (result.success) {
                await this.executeCommand('sudo ufw --force enable');
                return { success: true, method: 'ufw' };
            }
        }
        
        // firewall-cmd (RHEL/CentOS/Fedora)
        if (await this.commandExists('firewall-cmd')) {
            const result = await this.executeCommand(
                `sudo firewall-cmd --permanent --add-port=${port}/${protocol}`
            );
            if (result.success) {
                await this.executeCommand('sudo firewall-cmd --reload');
                return { success: true, method: 'firewall-cmd' };
            }
        }
        
        // iptables (fallback)
        if (await this.commandExists('iptables')) {
            const result = await this.executeCommand(
                `sudo iptables -A INPUT -p ${protocol} --dport ${port} -j ACCEPT`
            );
            if (result.success) {
                // Try to save iptables rules
                if (await this.commandExists('iptables-save')) {
                    await this.executeCommand('sudo iptables-save > /etc/iptables/rules.v4');
                }
                return { success: true, method: 'iptables' };
            }
        }
        
        return { 
            success: false, 
            error: 'No supported firewall manager found' 
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
        // Check for desktop environment indicators
        return !!(
            process.env.DISPLAY ||
            process.env.DESKTOP_SESSION ||
            process.env.XDG_CURRENT_DESKTOP ||
            process.env.GNOME_DESKTOP_SESSION_ID ||
            process.env.KDE_FULL_SESSION
        );
    }

    async getSystemInfo() {
        const info = {};
        
        // Get distribution info
        try {
            const osRelease = await this.executeCommand('cat /etc/os-release');
            if (osRelease.success) {
                const lines = osRelease.stdout.split('\n');
                lines.forEach(line => {
                    const [key, value] = line.split('=');
                    if (key && value) {
                        info[key.toLowerCase()] = value.replace(/"/g, '');
                    }
                });
            }
        } catch (e) {}
        
        // Get kernel version
        try {
            const kernel = await this.executeCommand('uname -r');
            if (kernel.success) {
                info.kernel = kernel.stdout.trim();
            }
        } catch (e) {}
        
        return info;
    }

    async checkDockerPermissions() {
        // Check if user can run docker without sudo
        const result = await this.executeCommand('docker ps', { timeout: 5000 });
        
        if (!result.success && result.stderr.includes('permission denied')) {
            return {
                hasPermission: false,
                suggestion: 'Add your user to the docker group: sudo usermod -aG docker $USER'
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
            } catch (e) {
                info.running = false;
            }
        } else {
            info.running = false;
        }
        
        return info;
    }

    async installNodeJs() {
        // Try to install Node.js using available package managers
        
        // Check for apt (Debian/Ubuntu)
        if (await this.commandExists('apt-get')) {
            // Add NodeSource repository
            await this.executeCommand('curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -');
            return this.executeCommand('sudo apt-get install -y nodejs');
        }
        
        // Check for yum/dnf (RHEL/CentOS/Fedora)
        if (await this.commandExists('dnf')) {
            await this.executeCommand('curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -');
            return this.executeCommand('sudo dnf install -y nodejs');
        } else if (await this.commandExists('yum')) {
            await this.executeCommand('curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -');
            return this.executeCommand('sudo yum install -y nodejs');
        }
        
        // Check for pacman (Arch)
        if (await this.commandExists('pacman')) {
            return this.executeCommand('sudo pacman -S --noconfirm nodejs npm');
        }
        
        // Check for zypper (openSUSE)
        if (await this.commandExists('zypper')) {
            return this.executeCommand('sudo zypper install -y nodejs npm');
        }
        
        return {
            success: false,
            error: 'No supported package manager found for Node.js installation'
        };
    }

    getEnvironmentVariables() {
        return {
            // Set HOST based on desktop vs server
            HOST: this.isDesktopEnvironment() ? 'localhost' : '0.0.0.0'
        };
    }
}

module.exports = LinuxPlatform;