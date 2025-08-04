#!/usr/bin/env node

/**
 * Encryption Integration for Provisioning App
 * Integrates SOPS + Age encryption for .env backups
 */

const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');
const execAsync = promisify(exec);

class EncryptionManager {
    constructor(projectRoot) {
        this.projectRoot = projectRoot;
        this.envBackupDir = path.join(projectRoot, 'deploy/docker/env-backups');
        this.sopsDir = path.join(projectRoot, '.sops');
        this.ageKeyFile = path.join(this.sopsDir, 'age-key.txt');
        this.agePublicKeyFile = path.join(this.sopsDir, 'age-public-key.txt');
        this.sopsConfig = path.join(projectRoot, '.sops.yaml');
        this.toolsDir = path.join(__dirname, 'tools');
    }

    /**
     * Check if encryption tools are available
     */
    async checkDependencies() {
        const dependencies = {
            sops: false,
            age: false,
            ageKeysExist: false
        };

        try {
            // Check SOPS
            await execAsync('which sops');
            dependencies.sops = true;
        } catch (e) {
            // SOPS not found
        }

        try {
            // Check Age
            await execAsync('which age');
            dependencies.age = true;
        } catch (e) {
            // Age not found
        }

        try {
            // Check if Age keys exist
            await fs.access(this.ageKeyFile);
            dependencies.ageKeysExist = true;
        } catch (e) {
            // Keys don't exist
        }

        return dependencies;
    }

    /**
     * Setup encryption if not already configured
     */
    async setupEncryption() {
        try {
            // Create .sops directory
            await fs.mkdir(this.sopsDir, { recursive: true });

            // Check if keys already exist
            try {
                await fs.access(this.ageKeyFile);
                console.log('Encryption keys already exist');
                return await this.getPublicKey();
            } catch (e) {
                // Keys don't exist, generate them
            }

            // Generate Age key pair
            const { stdout } = await execAsync('age-keygen');
            await fs.writeFile(this.ageKeyFile, stdout, { mode: 0o600 });

            // Extract public key
            const publicKeyMatch = stdout.match(/# public key: (age\w+)/);
            if (publicKeyMatch) {
                const publicKey = publicKeyMatch[1];
                await fs.writeFile(this.agePublicKeyFile, publicKey);

                // Create SOPS config
                const sopsConfig = `creation_rules:
  - path_regex: \.env.*\.encrypted$
    age: ${publicKey}
`;
                await fs.writeFile(this.sopsConfig, sopsConfig);

                return publicKey;
            }

            throw new Error('Failed to extract public key from age-keygen output');
        } catch (error) {
            console.error('Failed to setup encryption:', error);
            throw error;
        }
    }

    /**
     * Get the public key
     */
    async getPublicKey() {
        try {
            const publicKey = await fs.readFile(this.agePublicKeyFile, 'utf8');
            return publicKey.trim();
        } catch (error) {
            return null;
        }
    }

    /**
     * Create encrypted backup of .env file
     */
    async createEncryptedBackup(envFile, description = '') {
        try {
            const deps = await this.checkDependencies();
            if (!deps.sops || !deps.age) {
                console.log('Encryption tools not available, creating unencrypted backup');
                return await this.createUnencryptedBackup(envFile, description);
            }

            if (!deps.ageKeysExist) {
                console.log('Setting up encryption...');
                await this.setupEncryption();
            }

            // Create backup directory
            await fs.mkdir(this.envBackupDir, { recursive: true });

            // Generate timestamp
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
            const backupName = `env-${timestamp}`;
            const backupPath = path.join(this.envBackupDir, `${backupName}.env`);
            const encryptedPath = `${backupPath}.encrypted`;

            // Copy .env to backup location
            await fs.copyFile(envFile, backupPath);

            // Encrypt the backup
            const publicKey = await this.getPublicKey();
            const { stdout, stderr } = await execAsync(
                `SOPS_AGE_RECIPIENTS="${publicKey}" sops -e "${backupPath}" > "${encryptedPath}"`,
                { shell: true }
            );

            if (stderr) {
                console.error('SOPS warning:', stderr);
            }

            // Remove unencrypted backup
            await fs.unlink(backupPath);

            // Update metadata
            await this.updateMetadata(backupName, description, true);

            return {
                backupName,
                encryptedPath,
                encrypted: true,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            console.error('Failed to create encrypted backup:', error);
            // Fall back to unencrypted backup
            return await this.createUnencryptedBackup(envFile, description);
        }
    }

    /**
     * Create unencrypted backup (fallback)
     */
    async createUnencryptedBackup(envFile, description = '') {
        try {
            // Create backup directory
            await fs.mkdir(this.envBackupDir, { recursive: true });

            // Generate timestamp
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
            const backupName = `env-${timestamp}`;
            const backupPath = path.join(this.envBackupDir, `${backupName}.env`);

            // Copy .env to backup location
            await fs.copyFile(envFile, backupPath);
            await fs.chmod(backupPath, 0o600);

            // Update metadata
            await this.updateMetadata(backupName, description, false);

            return {
                backupName,
                backupPath,
                encrypted: false,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            console.error('Failed to create unencrypted backup:', error);
            throw error;
        }
    }

    /**
     * Update backup metadata
     */
    async updateMetadata(backupName, description, encrypted) {
        try {
            const metadataPath = path.join(this.envBackupDir, 'metadata.json');
            let metadata = { versions: [], current: null };

            // Read existing metadata
            try {
                const data = await fs.readFile(metadataPath, 'utf8');
                metadata = JSON.parse(data);
            } catch (e) {
                // File doesn't exist, use default
            }

            // Add new version
            metadata.versions.push({
                name: backupName,
                timestamp: new Date().toISOString(),
                description: description || 'Backup created by provisioning app',
                encrypted,
                createdBy: 'provisioning-app'
            });

            // Keep only last 50 versions
            if (metadata.versions.length > 50) {
                metadata.versions = metadata.versions.slice(-50);
            }

            // Update current
            metadata.current = backupName;

            // Write metadata
            await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2));
        } catch (error) {
            console.error('Failed to update metadata:', error);
        }
    }

    /**
     * List available backups
     */
    async listBackups() {
        try {
            const metadataPath = path.join(this.envBackupDir, 'metadata.json');
            const data = await fs.readFile(metadataPath, 'utf8');
            const metadata = JSON.parse(data);
            return metadata.versions || [];
        } catch (error) {
            return [];
        }
    }

    /**
     * Restore a backup
     */
    async restoreBackup(backupName, targetPath) {
        try {
            const backupPath = path.join(this.envBackupDir, `${backupName}.env`);
            const encryptedPath = `${backupPath}.encrypted`;

            // Check if encrypted version exists
            try {
                await fs.access(encryptedPath);
                
                // Decrypt the backup
                const tempPath = `${backupPath}.temp`;
                const { stdout, stderr } = await execAsync(
                    `SOPS_AGE_KEY_FILE="${this.ageKeyFile}" sops -d "${encryptedPath}" > "${tempPath}"`,
                    { shell: true }
                );

                if (stderr) {
                    console.error('SOPS warning:', stderr);
                }

                // Copy decrypted file to target
                await fs.copyFile(tempPath, targetPath);
                await fs.chmod(targetPath, 0o600);

                // Clean up temp file
                await fs.unlink(tempPath);

                return { success: true, encrypted: true };
            } catch (e) {
                // Try unencrypted backup
                await fs.access(backupPath);
                await fs.copyFile(backupPath, targetPath);
                await fs.chmod(targetPath, 0o600);
                return { success: true, encrypted: false };
            }
        } catch (error) {
            console.error('Failed to restore backup:', error);
            throw error;
        }
    }

    /**
     * Install encryption tools
     */
    async installTools() {
        const script = `#!/bin/bash
# Install SOPS
if ! command -v sops &> /dev/null; then
    echo "Installing SOPS..."
    wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 -O ~/bin/sops
    chmod +x ~/bin/sops
fi

# Install Age
if ! command -v age &> /dev/null; then
    echo "Installing Age..."
    wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
    tar -xzf age-v1.1.1-linux-amd64.tar.gz
    mv age/age ~/bin/
    mv age/age-keygen ~/bin/
    rm -rf age age-v1.1.1-linux-amd64.tar.gz
fi

echo "Encryption tools installed successfully"
`;
        
        try {
            await fs.mkdir(path.expanduser('~/bin'), { recursive: true });
            const { stdout, stderr } = await execAsync(script, { shell: '/bin/bash' });
            console.log(stdout);
            if (stderr) console.error(stderr);
            return true;
        } catch (error) {
            console.error('Failed to install tools:', error);
            return false;
        }
    }
}

module.exports = EncryptionManager;