# Provisioning App Testing Guide

## Overview
This guide provides comprehensive testing procedures for the AI Stack Master provisioning system to ensure reliable deployment across different environments.

## Pre-Testing Checklist

### Environment Requirements
- [ ] Docker version 20.10+ installed
- [ ] Docker Compose v2+ installed
- [ ] At least 20GB free disk space
- [ ] 4GB+ RAM available
- [ ] Internet connection for image pulls
- [ ] Port 8080 available for provisioning UI

### Clean Environment Setup
```bash
# Ensure clean state before testing
docker ps -aq | xargs -r docker stop
docker system prune -af --volumes
rm -f deploy/docker/.env
rm -rf deploy/docker/env-backups/*
```

## Test Scenarios

### 1. Fresh Installation Test

#### Steps:
1. **Run bootstrap script**
   ```bash
   ./provision.sh
   ```

2. **Verify prerequisites check**
   - Should detect Docker and Docker Compose
   - Should report no existing installation
   - Should offer firewall configuration

3. **Access provisioning UI**
   - Navigate to http://localhost:8080
   - Verify UI loads without errors
   - Check browser console for JavaScript errors

4. **Configure deployment**
   - Enter test domain: `test.local`
   - Enter admin email: `admin@test.local`
   - Select SSL provider: `None (Local Development)`
   - Generate passwords automatically

5. **Start deployment**
   - Click "Start Deployment"
   - Monitor real-time progress
   - Verify all 13 steps complete

6. **Verify services**
   - Check all URLs are accessible
   - Verify health status shows green
   - Test login with generated credentials

#### Expected Results:
- All steps complete without errors
- Services accessible at configured URLs
- Authentication working correctly

### 2. Existing Installation Detection Test

#### Setup:
```bash
# Create a dummy .env file
echo "DOMAIN=existing.local" > deploy/docker/.env
```

#### Steps:
1. **Run bootstrap script**
   ```bash
   ./provision.sh
   ```

2. **Verify existing installation detection**
   - Should detect existing .env
   - Should offer Reconfigure/Upgrade/Cancel options

3. **Test Reconfigure option**
   - Select 'R' for reconfigure
   - Verify backup is created
   - Complete new configuration

#### Expected Results:
- Existing .env backed up with timestamp
- New configuration generated successfully
- Previous .env preserved in backups

### 3. SSL Provider Tests

#### Test 3.1: Cloudflare Tunnel
1. **Configure with Cloudflare Tunnel**
   - Domain: `tunnel.example.com`
   - SSL Provider: `Cloudflare Tunnel`
   - Provide tunnel token when prompted

2. **Verify configuration**
   - Check .env contains `CF_TUNNEL_TOKEN`
   - Verify tunnel configuration in deployment

#### Test 3.2: Cloudflare API
1. **Configure with Cloudflare API**
   - Domain: `api.example.com`
   - SSL Provider: `Cloudflare API`
   - Provide API token and Zone ID

2. **Verify configuration**
   - Check .env contains CF API credentials
   - Verify DNS configuration attempted

#### Test 3.3: Nginx Proxy Manager
1. **Configure with NPM**
   - Domain: `npm.example.com`
   - SSL Provider: `Nginx Proxy Manager`

2. **Verify configuration**
   - Check NPM container starts
   - Verify NPM accessible on port 81

### 4. Validation Tests

#### Test 4.1: Invalid Domain
1. **Enter invalid domain**
   - Try: `not a domain`
   - Try: `localhost` (when not using None provider)
   - Try: `example` (no TLD)

2. **Verify validation**
   - Should show appropriate error messages
   - Should not allow deployment to proceed

#### Test 4.2: Port Conflicts
1. **Start a service on port 3000**
   ```bash
   docker run -d -p 3000:80 --name test-conflict nginx
   ```

2. **Run provisioning**
   - Should detect port conflict
   - Should show warning in validation

3. **Cleanup**
   ```bash
   docker stop test-conflict && docker rm test-conflict
   ```

### 5. Error Recovery Tests

#### Test 5.1: Network Failure Simulation
1. **Start deployment**
2. **During image pull, disconnect network briefly**
3. **Verify retry mechanism**
   - Should show retry option
   - Should resume from failed step

#### Test 5.2: Disk Space Exhaustion
1. **Fill disk to near capacity**
   ```bash
   # Create large file (adjust size as needed)
   dd if=/dev/zero of=/tmp/largefile bs=1G count=10
   ```

2. **Attempt deployment**
   - Should fail gracefully
   - Should show disk space error

3. **Cleanup**
   ```bash
   rm /tmp/largefile
   ```

### 6. WebSocket Connection Test

#### Steps:
1. **Open browser developer tools**
2. **Go to Network tab, filter by WS**
3. **Start deployment**
4. **Verify WebSocket**
   - Connection establishes
   - Real-time updates received
   - No disconnection errors

### 7. Multi-Browser Compatibility Test

Test the provisioning UI in:
- [ ] Chrome/Chromium
- [ ] Firefox
- [ ] Safari (if on macOS)
- [ ] Edge

Verify:
- UI renders correctly
- WebSocket connections work
- Progress updates display
- No console errors

### 8. Performance Tests

#### Test 8.1: Large Log Output
1. **Monitor deployment logs**
2. **Verify performance with high log volume**
   - UI remains responsive
   - Log viewer doesn't freeze
   - Memory usage stays reasonable

#### Test 8.2: Slow Network Simulation
```bash
# Simulate slow network (Linux)
sudo tc qdisc add dev eth0 root netem delay 200ms
```

1. **Run deployment**
2. **Verify timeout handling**
3. **Cleanup**
   ```bash
   sudo tc qdisc del dev eth0 root
   ```

## Post-Deployment Verification

### Service Health Checks
```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verify health status
docker ps --filter health=healthy --format "{{.Names}}"

# Check service endpoints
curl -s http://localhost:3001/api/health | jq .
curl -s http://localhost:3002/api/health | jq .
curl -s http://localhost:3000/api/health
curl -s http://localhost:9090/-/healthy
```

### Authentication Tests
1. **Test Stack Manager login**
   - URL: http://localhost:3001
   - Use generated credentials
   - Verify JWT token issued

2. **Test Grafana SSO**
   - URL: http://localhost:3000
   - Should auto-login via GoTrue
   - Verify user created

3. **Test n8n access**
   - URL: http://localhost:5678
   - Login with master credentials
   - Verify API key generated

## Troubleshooting Procedures

### Provisioning Container Issues
```bash
# Check container logs
docker compose -f docker-compose.provisioning.yml logs -f

# Inspect container
docker exec -it ai-stack-provisioning sh

# Check file permissions
docker exec ai-stack-provisioning ls -la /workspace/deploy/docker/

# Verify Docker socket access
docker exec ai-stack-provisioning docker ps
```

### Deployment Failures
1. **Check deployment logs**
   ```bash
   # From provisioning container
   docker exec ai-stack-provisioning cat /app/data/deployments/*/install.log
   ```

2. **Verify script execution**
   ```bash
   # Check if scripts are executable
   ls -la deploy/scripts/
   ```

3. **Environment validation**
   ```bash
   # Validate generated .env
   cat deploy/docker/.env | grep -E "^[A-Z_]+=" | wc -l
   ```

## Cleanup Procedures

### After Testing
```bash
# Stop all services
./install.sh down

# Remove provisioning container
docker compose -f docker-compose.provisioning.yml down -v

# Clean up test data
rm -rf deploy/docker/.env*
rm -rf deploy/docker/env-backups/*

# Remove all containers and volumes
docker compose down -v
docker system prune -af --volumes
```

## Regression Test Checklist

Before any release, verify:

- [ ] Fresh installation completes successfully
- [ ] Existing installation detection works
- [ ] All SSL providers configure correctly
- [ ] Validation catches common errors
- [ ] Error recovery mechanisms function
- [ ] WebSocket updates work reliably
- [ ] All services start and pass health checks
- [ ] Authentication flow works end-to-end
- [ ] UI is responsive and error-free
- [ ] Cleanup procedures work correctly

## Automated Testing (Future)

### Unit Tests
```bash
cd apps/provisioning-web/backend
npm test
```

### Integration Tests
```bash
# Run automated provisioning tests
./test/provisioning/run-integration-tests.sh
```

### E2E Tests
```bash
# Run Playwright tests
npx playwright test provisioning.spec.js
```

## Reporting Issues

When reporting provisioning issues, include:

1. **Environment details**
   ```bash
   docker version
   docker compose version
   uname -a
   free -h
   df -h
   ```

2. **Provisioning logs**
   ```bash
   docker compose -f docker-compose.provisioning.yml logs > provisioning.log
   ```

3. **Deployment state**
   ```bash
   cat apps/provisioning-web/backend/.provision-state.json
   ```

4. **Generated configuration** (sanitized)
   ```bash
   grep -E "^[A-Z_]+=" deploy/docker/.env | sed 's/=.*/=<REDACTED>/'
   ```

This comprehensive testing ensures the provisioning system works reliably across different scenarios and environments.