const PlatformBase = require('./base');
const path = require('path');

/**
 * Windows platform-specific operations
 */
class WindowsPlatform extends PlatformBase {
    constructor() {
        super();
        this.isWSL = this.detectWSL();
    }

    detectWSL() {
        // Check if running in WSL
        try {
            const fs = require('fs');
            const procVersion = fs.readFileSync('/proc/version', 'utf8');
            return procVersion.toLowerCase().includes('microsoft');
        } catch (e) {
            return false;
        }
    }

    async runDockerCompose(action, cwd, options = {}) {
        // Windows Docker Desktop uses docker.exe
        const dockerCmd = this.isWSL ? 'docker' : 'docker.exe';
        
        // Try docker compose v2 first
        let command = `${dockerCmd} compose ${action}`;
        let result = await this.executeCommand(command, { 
            cwd: this.translatePath(cwd), 
            shell: 'powershell.exe',
            ...options 
        });
        
        // Fallback to docker-compose if v2 fails
        if (!result.success) {
            command = `docker-compose ${action}`;
            result = await this.executeCommand(command, { 
                cwd: this.translatePath(cwd),
                shell: 'powershell.exe',
                ...options 
            });
        }
        
        return result;
    }

    async openFirewallPort(port, protocol = 'tcp') {
        const ruleName = `Stack Masters ${port}`;
        
        // Check if rule already exists
        const checkCmd = `Get-NetFirewallRule -DisplayName "${ruleName}" -ErrorAction SilentlyContinue`;
        const checkResult = await this.executeCommand(checkCmd, { shell: 'powershell.exe' });
        
        if (checkResult.success && checkResult.stdout.trim()) {
            return { success: true, message: 'Firewall rule already exists' };
        }
        
        // Create new firewall rule
        const createCmd = `New-NetFirewallRule -DisplayName "${ruleName}" ` +
            `-Direction Inbound -Protocol ${protocol.toUpperCase()} ` +
            `-LocalPort ${port} -Action Allow`;
        
        const result = await this.executeCommand(createCmd, { shell: 'powershell.exe' });
        
        return {
            success: result.success,
            method: 'Windows Firewall',
            error: result.error
        };
    }

    async commandExists(command) {
        // Use Get-Command for PowerShell
        const checkCmd = `Get-Command ${command} -ErrorAction SilentlyContinue`;
        const result = await this.executeCommand(checkCmd, { shell: 'powershell.exe' });
        return result.success && result.stdout.trim() !== '';
    }

    async hasElevatedPrivileges() {
        const checkCmd = `([Security.Principal.WindowsPrincipal] ` +
            `[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(` +
            `[Security.Principal.WindowsBuiltInRole] "Administrator")`;
        
        const result = await this.executeCommand(checkCmd, { shell: 'powershell.exe' });
        return result.success && result.stdout.trim().toLowerCase() === 'true';
    }

    getDockerCommand() {
        // Use docker.exe to ensure we're calling Windows Docker Desktop
        return this.isWSL ? 'docker' : 'docker.exe';
    }

    translatePath(inputPath) {
        if (!inputPath) return inputPath;
        
        // If running in WSL, paths are already Linux-style
        if (this.isWSL) return inputPath;
        
        // Convert Windows path to WSL path format if needed
        // C:\Users\name\project -> /mnt/c/Users/name/project
        if (inputPath.match(/^[A-Z]:\\/i)) {
            const drive = inputPath[0].toLowerCase();
            const pathWithoutDrive = inputPath.substring(2).replace(/\\/g, '/');
            return `/mnt/${drive}${pathWithoutDrive}`;
        }
        
        // Already a Unix-style path
        return inputPath;
    }

    isDesktopEnvironment() {
        // Windows with a GUI is always a desktop environment
        // Check if we're on Windows Server Core (no GUI)
        return !process.env.SERVER_CORE;
    }

    getShell() {
        return 'powershell.exe';
    }

    async getSystemInfo() {
        const info = {};
        
        // Get Windows version
        const versionCmd = 'Get-CimInstance -ClassName Win32_OperatingSystem | ' +
            'Select-Object Caption, Version, BuildNumber | ConvertTo-Json';
        
        const versionResult = await this.executeCommand(versionCmd, { shell: 'powershell.exe' });
        if (versionResult.success) {
            try {
                const versionInfo = JSON.parse(versionResult.stdout);
                info.caption = versionInfo.Caption;
                info.version = versionInfo.Version;
                info.build = versionInfo.BuildNumber;
            } catch (e) {}
        }
        
        // Check if Windows Server
        const productTypeCmd = '(Get-CimInstance -ClassName Win32_OperatingSystem).ProductType';
        const productResult = await this.executeCommand(productTypeCmd, { shell: 'powershell.exe' });
        if (productResult.success) {
            // ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
            info.isServer = productResult.stdout.trim() !== '1';
        }
        
        return info;
    }

    async checkDockerPermissions() {
        // On Windows, check if Docker Desktop is running
        const dockerCmd = this.getDockerCommand();
        const result = await this.executeCommand(`${dockerCmd} ps`, { 
            shell: 'powershell.exe',
            timeout: 5000 
        });
        
        if (!result.success) {
            if (result.stderr.includes('error during connect')) {
                return {
                    hasPermission: false,
                    suggestion: 'Docker Desktop is not running. Please start Docker Desktop.'
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
        const dockerCmd = this.getDockerCommand();
        
        // Check Docker version
        const versionResult = await this.executeCommand(
            `${dockerCmd} --version`,
            { shell: 'powershell.exe' }
        );
        if (versionResult.success) {
            info.version = versionResult.stdout.trim();
        }
        
        // Check if Docker daemon is running
        const infoResult = await this.executeCommand(
            `${dockerCmd} info --format json`,
            { shell: 'powershell.exe' }
        );
        if (infoResult.success) {
            try {
                const dockerInfo = JSON.parse(infoResult.stdout);
                info.running = true;
                info.serverVersion = dockerInfo.ServerVersion;
                info.storageDriver = dockerInfo.Driver;
                info.dockerRootDir = dockerInfo.DockerRootDir;
                info.osType = dockerInfo.OSType; // Should be 'linux' even on Windows
            } catch (e) {
                info.running = false;
            }
        } else {
            info.running = false;
        }
        
        return info;
    }

    async installNodeJs() {
        // Check if winget is available
        if (await this.commandExists('winget')) {
            return this.executeCommand(
                'winget install --id OpenJS.NodeJS --exact --silent --accept-package-agreements --accept-source-agreements',
                { shell: 'powershell.exe' }
            );
        }
        
        // Fallback to Chocolatey if available
        if (await this.commandExists('choco')) {
            return this.executeCommand(
                'choco install nodejs -y',
                { shell: 'powershell.exe' }
            );
        }
        
        return {
            success: false,
            error: 'No supported package manager found. Please install Node.js manually.'
        };
    }

    getEnvironmentVariables() {
        const systemInfo = this.getSystemInfo();
        
        return {
            // Set HOST based on server vs desktop
            HOST: systemInfo.isServer ? '0.0.0.0' : 'localhost',
            // Force color output in Windows terminal
            FORCE_COLOR: '1'
        };
    }

    async isPortAvailable(port) {
        const checkCmd = `Get-NetTCPConnection -LocalPort ${port} -ErrorAction SilentlyContinue`;
        const result = await this.executeCommand(checkCmd, { shell: 'powershell.exe' });
        
        // If command succeeds and returns output, port is in use
        return !result.success || !result.stdout.trim();
    }
}

module.exports = WindowsPlatform;