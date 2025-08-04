# AI Stack Master - Provisioning System

> 📚 **Complete Documentation Available**: See [README_COMPLETE.md](./README_COMPLETE.md) for the full consolidated documentation including architecture, API reference, troubleshooting, and advanced topics.

## Quick Links
- 📖 [Complete Documentation](./README_COMPLETE.md) - Everything you need to know
- 🗂️ [Documentation Index](./DOCUMENTATION_INDEX.md) - All documentation files
- 🚀 [Quick Start](#quick-start) - Get started in 2 minutes
- 🔧 [Troubleshooting](./README_COMPLETE.md#troubleshooting) - Common issues

## Overview
The provisioning system is the **first point of entry** for deploying the AI Stack Master. It provides a web-based interface that handles:

- Environment configuration (.env generation)
- SSL/DNS setup (including Cloudflare integration)
- Firewall configuration
- Docker stack deployment
- Service health verification

## Quick Start

### Option 1: Fresh Server (Recommended)
```bash
# Clone the repository
git clone https://github.com/Tech-to-Thrive/agent-hosting.git
cd agent-hosting

# Run the provisioning bootstrap
./provision.sh
```

### Option 2: Direct Docker Run
```bash
# From the project root
docker compose -f docker-compose.provisioning.yml up -d

# Access at http://localhost:8080
```

## Architecture

### Bootstrap Flow
1. **provision.sh** - Initial script that:
   - Checks prerequisites (Docker, Docker Compose)
   - Detects existing installations
   - Configures firewall rules
   - Starts provisioning container

2. **Provisioning Container** - Runs the web interface:
   - Validates configuration
   - Generates .env file
   - Executes install.sh
   - Monitors deployment progress
   - Verifies service health

3. **Main Stack** - Deployed by provisioning:
   - All services configured via generated .env
   - SSL/DNS configured based on user selection
   - Automatic health checks and verification

### Key Features

#### Existing Installation Detection
- Checks for existing .env file
- Detects running containers
- Offers reconfigure/upgrade options
- Backs up existing configuration

#### SSL/DNS Options
1. **None** - Local development
2. **Cloudflare Tunnel** - Zero-trust tunnels (recommended)
3. **Cloudflare API** - Traditional DNS management
4. **Nginx Proxy Manager** - Self-managed SSL

#### Validation & Verification
- Pre-deployment validation:
  - Domain format and DNS resolution
  - Port availability checks
  - Docker/environment validation
  - SSL configuration validation

- Post-deployment verification:
  - Service health checks
  - URL accessibility tests
  - Critical service monitoring

## File Structure
```
apps/provisioning-web/
├── backend/
│   ├── server-integrated.js    # Main server with install.sh integration
│   ├── validators.js           # Configuration validation
│   ├── post-deploy-check.js   # Service verification
│   └── package.json
├── frontend/                   # React UI (if needed)
├── Dockerfile                  # Container with Docker CLI
├── CLOUDFLARE_SETUP.md        # Cloudflare integration guide
└── README.md                  # This file
```

## Environment Variables
The provisioning container uses:
- `PROJECT_ROOT` - Path to project root (default: auto-detected)
- `PORT` - Web interface port (default: 8080)
- `NODE_ENV` - Environment (default: production)

## Security Considerations

### Network Security
- Provisioning interface is unprotected (temporary use only)
- Automatically configures firewall rules for required ports
- Supports Cloudflare zero-trust tunnels for production

### Configuration Security
- Passwords auto-generated if not provided
- Existing .env files backed up before modification
- API tokens validated but never logged

## Deployment Workflow

1. **User runs provision.sh**
   - Prerequisites checked
   - Firewall configured
   - Provisioning container started

2. **User accesses web interface**
   - Configures domain, email, SSL
   - Validates configuration
   - Starts deployment

3. **Provisioning executes**
   - Generates .env via generate-env-config.sh
   - Runs install.sh with real-time progress
   - Verifies all services are accessible

4. **Deployment complete**
   - Shows accessible URLs
   - Provisioning container can be stopped
   - Stack runs independently

## Troubleshooting

### Provisioning container won't start
```bash
# Check logs
docker compose -f docker-compose.provisioning.yml logs

# Verify Docker socket mounted
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine ls -la /var/run/docker.sock
```

### Can't access web interface
- Check firewall allows port 8080
- Verify container is running: `docker ps`
- Check health: `curl http://localhost:8080/api/health`

### Deployment fails
- Check validation errors in UI
- Monitor logs in deployment view
- Verify all prerequisites installed
- Check disk space and permissions

## Development

### Running locally
```bash
cd apps/provisioning-web/backend
npm install
npm start
```

### Building container
```bash
docker build -t ai-stack-provisioning apps/provisioning-web/
```

### Testing
```bash
# Validate configuration
curl -X POST http://localhost:8080/api/validate \
  -H "Content-Type: application/json" \
  -d '{"domain": "example.com", "adminEmail": "admin@example.com"}'

# Check existing installation
curl http://localhost:8080/api/check-existing

# Verify deployment
curl -X POST http://localhost:8080/api/verify-deployment \
  -H "Content-Type: application/json" \
  -d '{"domain": "localhost"}'
```