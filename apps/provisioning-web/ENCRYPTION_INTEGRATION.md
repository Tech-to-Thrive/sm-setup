# Provisioning App - Encryption Integration

## Overview

The provisioning app now includes integrated support for **encrypted .env backups** using SOPS (Secrets Operations) with Age encryption. This provides enterprise-grade security for configuration backups while maintaining ease of use.

## Features

✅ **Automatic Encrypted Backups** - Every deployment creates an encrypted backup  
✅ **Fallback to Unencrypted** - Works even without encryption tools installed  
✅ **One-Click Tool Installation** - Install encryption tools from the UI  
✅ **Backup Management** - List and restore previous configurations  
✅ **Zero Configuration** - Encryption keys generated automatically  

## How It Works

### During Deployment

1. When you deploy through the provisioning app, after the .env file is generated:
   - The system checks if encryption tools (SOPS + Age) are available
   - If available, creates an encrypted backup automatically
   - If not available, creates an unencrypted backup with secure permissions (600)

2. All backups are stored in:
   ```
   deploy/docker/env-backups/
   ├── metadata.json           # Backup registry
   ├── env-2025-01-10.env.encrypted  # Encrypted backups
   └── env-2025-01-09.env     # Unencrypted backups (fallback)
   ```

### Encryption Architecture

```
.env file → SOPS + Age Encryption → .env.encrypted
                    ↓
              Age Key Pair
          (stored in .sops/)
```

## API Endpoints

### Check Encryption Status
```bash
GET /api/encryption/status

Response:
{
  "available": true,      # Are tools installed?
  "configured": true,     # Are keys generated?
  "dependencies": {
    "sops": true,
    "age": true,
    "ageKeysExist": true
  },
  "publicKey": "age1..."  # Your public key
}
```

### List Backups
```bash
GET /api/backups

Response:
{
  "backups": [
    {
      "name": "env-2025-01-10T14-30-00",
      "timestamp": "2025-01-10T14:30:00.000Z",
      "description": "Provisioning deployment - example.com",
      "encrypted": true,
      "createdBy": "provisioning-app"
    }
  ]
}
```

### Restore Backup
```bash
POST /api/backups/restore
Content-Type: application/json

{
  "backupName": "env-2025-01-10T14-30-00"
}

Response:
{
  "success": true,
  "message": "Restored encrypted backup successfully",
  "backupName": "env-2025-01-10T14-30-00"
}
```

### Install Encryption Tools
```bash
POST /api/encryption/install

Response:
{
  "success": true,
  "message": "Encryption tools installed and configured",
  "publicKey": "age1..."
}
```

## Manual Usage

### Check Encryption Status
```bash
curl http://localhost:8080/api/encryption/status | jq .
```

### View Available Backups
```bash
curl http://localhost:8080/api/backups | jq .
```

### Restore a Backup
```bash
# List backups first
curl http://localhost:8080/api/backups | jq .

# Restore specific backup
curl -X POST http://localhost:8080/api/backups/restore \
  -H "Content-Type: application/json" \
  -d '{"backupName": "env-2025-01-10T14-30-00"}'
```

### Install Encryption Tools
```bash
# One-time installation
curl -X POST http://localhost:8080/api/encryption/install
```

## Security Details

### Encryption Method
- **Algorithm**: Age (modern encryption tool by FiloSottile)
- **Integration**: SOPS (Mozilla's secrets management)
- **Key Storage**: Local filesystem in `.sops/` directory
- **Permissions**: All keys and backups use 600 permissions

### Key Management
```
.sops/
├── age-key.txt         # Private key (chmod 600)
├── age-public-key.txt  # Public key for sharing
└── .sops.yaml         # SOPS configuration
```

### Backup Security
- Encrypted backups use `.env.encrypted` extension
- Unencrypted fallbacks use standard `.env` extension
- All files have restrictive permissions (600)
- Metadata tracks encryption status of each backup

## Troubleshooting

### "Encryption tools not available"
The system will still create unencrypted backups. To enable encryption:
1. Click "Install Encryption Tools" in the UI, or
2. Run: `curl -X POST http://localhost:8080/api/encryption/install`

### "Failed to create encrypted backup"
Possible causes:
- Insufficient permissions in `deploy/docker/env-backups/`
- Corrupted Age keys in `.sops/`
- Disk space issues

### "Cannot restore backup"
Check:
- Backup file exists in `deploy/docker/env-backups/`
- For encrypted backups, Age keys exist in `.sops/`
- File permissions allow reading

## Manual Encryption Management

If you prefer to manage encryption manually:

### Install Tools Manually
```bash
# Install SOPS
wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
chmod +x sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops

# Install Age
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar -xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age* /usr/local/bin/
```

### Generate Keys Manually
```bash
# Generate Age key pair
age-keygen -o .sops/age-key.txt

# Extract public key
grep "public key:" .sops/age-key.txt | cut -d: -f2 | tr -d ' ' > .sops/age-public-key.txt
```

### Create Encrypted Backup Manually
```bash
# Set recipient
export SOPS_AGE_RECIPIENTS=$(cat .sops/age-public-key.txt)

# Encrypt .env file
sops -e deploy/docker/.env > deploy/docker/env-backups/manual-backup.env.encrypted
```

### Restore Encrypted Backup Manually
```bash
# Set key file
export SOPS_AGE_KEY_FILE=.sops/age-key.txt

# Decrypt backup
sops -d deploy/docker/env-backups/backup.env.encrypted > deploy/docker/.env
chmod 600 deploy/docker/.env
```

## Integration with CI/CD

For automated deployments:

1. **Store Age public key** in CI/CD secrets
2. **Encrypt .env template** before committing
3. **Decrypt during deployment** using private key

Example GitHub Actions:
```yaml
- name: Decrypt environment
  env:
    SOPS_AGE_KEY: ${{ secrets.AGE_PRIVATE_KEY }}
  run: |
    echo "$SOPS_AGE_KEY" > /tmp/age-key.txt
    export SOPS_AGE_KEY_FILE=/tmp/age-key.txt
    sops -d .env.encrypted > .env
```

## Best Practices

1. **Regular Backups**: The system creates automatic backups on each deployment
2. **Test Restores**: Periodically test backup restoration
3. **Secure Key Storage**: Keep `.sops/age-key.txt` secure and backed up
4. **Rotation**: Consider rotating encryption keys quarterly
5. **Monitoring**: Check backup success in deployment logs

## Future Enhancements

- [ ] Automatic backup rotation (keep last N backups)
- [ ] Cloud backup integration (S3, GCS)
- [ ] Multi-key support for team access
- [ ] Backup integrity verification
- [ ] Scheduled automatic backups

## Summary

The encryption integration provides:
- **Automatic Protection**: Every deployment is backed up
- **Flexible Security**: Encrypted when possible, secure always
- **Easy Recovery**: One-click restore from any backup
- **Zero Friction**: Works out of the box, no configuration needed

This ensures your sensitive configuration data is protected while maintaining the simplicity of the provisioning workflow.