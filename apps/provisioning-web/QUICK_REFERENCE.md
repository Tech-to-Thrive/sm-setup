# AI Stack Master - Provisioning Quick Reference

## 🚀 Quick Start
```bash
git clone https://github.com/Tech-to-Thrive/agent-hosting.git
cd agent-hosting
./provision.sh
```
Access UI at: **http://localhost:8080**

## 📋 Pre-Flight Checklist
- ✅ Docker 20.10+ installed
- ✅ Docker Compose v2+ installed  
- ✅ 20GB free disk space
- ✅ 4GB+ available RAM
- ✅ Ports available: 8080, 3000-3002, 5678, 9090

## 🔧 Common Commands

### Provisioning Control
```bash
# Start provisioning
./provision.sh

# Check provisioning logs
docker compose -f docker-compose.provisioning.yml logs -f

# Stop provisioning (after deployment)
docker compose -f docker-compose.provisioning.yml down
```

### Stack Management
```bash
# Check stack status
docker ps --format "table {{.Names}}\t{{.Status}}"

# View all logs
docker compose logs -f

# Stop everything
./install.sh down

# Clean restart
./install.sh --clean
```

## 🌐 SSL/DNS Provider Quick Config

### None (Local Development)
- Domain: Use `localhost` or `*.local`
- No additional configuration needed
- Access via HTTP only

### Cloudflare Tunnel (Recommended)
1. Create tunnel at: https://one.dash.cloudflare.com/
2. Copy tunnel token
3. No port forwarding needed
4. Automatic SSL included

### Cloudflare API
1. Get API token: https://dash.cloudflare.com/profile/api-tokens
2. Required permissions: `Zone:Edit`
3. Get Zone ID from domain overview
4. Ports 80/443 must be accessible

### Nginx Proxy Manager
- Accessible at: http://localhost:81
- Default login: admin@example.com / changeme
- Manual SSL certificate management
- Requires ports 80/443 forwarded

## 🔑 Default Credentials

### Master Admin (all services)
- Email: Set during provisioning
- Password: Auto-generated or custom

### Service URLs
- **Stack Manager**: http://localhost:3001
- **Grafana**: http://localhost:3000
- **n8n**: http://localhost:5678
- **Prometheus**: http://localhost:9090
- **NPM** (if enabled): http://localhost:81

## 🚨 Troubleshooting

### Provisioning UI Not Loading
```bash
# Check container status
docker ps | grep provisioning

# Check logs
docker logs ai-stack-provisioning

# Test health endpoint
curl http://localhost:8080/api/health
```

### Deployment Stuck
```bash
# Check current step
curl http://localhost:8080/api/deploy/{deployment-id}/status

# View install.sh output
docker exec ai-stack-provisioning tail -f /app/data/deployments/*/install.log

# Retry failed step (in UI or via API)
curl -X POST http://localhost:8080/api/deploy/{deployment-id}/retry
```

### Services Not Starting
```bash
# Check Docker resources
docker system df
docker stats --no-stream

# Verify images downloaded
docker images | grep -E "(n8n|grafana|postgres|redis)"

# Check compose status
docker compose ps -a
```

### Port Conflicts
```bash
# Find what's using a port
sudo lsof -i :3000
sudo netstat -tlnp | grep 3000

# Kill process using port
sudo kill -9 $(sudo lsof -t -i:3000)
```

## 📊 Health Verification

### Quick Health Check
```bash
# All services healthy?
docker ps --filter health=healthy | wc -l
# Should show 15+ containers

# Check specific service
docker inspect app-n8n | jq '.[0].State.Health.Status'
```

### Service Endpoints
```bash
# Test all endpoints
for port in 3000 3001 3002 5678 9090; do
  echo -n "Port $port: "
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$port/
done
```

## 🔄 Common Operations

### Reconfigure Existing Installation
```bash
# Backup current config
cp deploy/docker/.env deploy/docker/.env.backup

# Run provisioning again
./provision.sh
# Select 'R' for reconfigure
```

### Update Stack
```bash
# Pull latest code
git pull

# Run provisioning
./provision.sh
# Select 'U' for upgrade
```

### Full Reset
```bash
# Stop everything
./install.sh down

# Remove all data
docker compose down -v
rm -rf deploy/docker/.env*

# Start fresh
./provision.sh
```

## 🔐 Security Notes

### Firewall Rules (UFW)
```bash
# Required for stack
sudo ufw allow 8080/tcp  # Provisioning (temporary)
sudo ufw allow 3000/tcp  # Grafana
sudo ufw allow 3001/tcp  # Stack Manager UI
sudo ufw allow 3002/tcp  # Stack Manager API
sudo ufw allow 5678/tcp  # n8n
sudo ufw allow 9090/tcp  # Prometheus

# For SSL (if using NPM)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Post-Deployment Security
1. Stop provisioning container after setup
2. Change default NPM password (if used)
3. Configure firewall rules
4. Set up SSL certificates
5. Enable 2FA where available

## 📱 Mobile Access

For mobile access to deployed stack:
1. Use Cloudflare Tunnel (recommended)
2. Or configure port forwarding + dynamic DNS
3. Always use HTTPS for external access
4. Consider VPN for additional security

## 💡 Pro Tips

1. **Save credentials**: The generated passwords are shown once - save them!
2. **Use screen/tmux**: For long-running deployments on remote servers
3. **Monitor resources**: Keep `docker stats` running in another terminal
4. **Check logs early**: Don't wait for timeout - check logs if step seems stuck
5. **Clean regularly**: Run `docker system prune -a` monthly to free space

## 🆘 Emergency Procedures

### Stack Unresponsive
```bash
# Force stop all containers
docker stop $(docker ps -aq)

# Clean restart
./install.sh --clean
```

### Disk Full
```bash
# Quick cleanup
docker system prune -af --volumes
# Remove old logs
find /var/lib/docker/containers -name "*.log" -size +100M -delete
```

### Complete Removal
```bash
# Stop and remove everything
docker compose down -v
docker system prune -af --volumes
rm -rf deploy/docker/
# Reinstall from scratch
```

---
**Remember**: The provisioning UI is temporary and unsecured. Always stop it after deployment completes!

For detailed documentation, see:
- `README.md` - Complete setup guide
- `PROVISIONING_ARCHITECTURE.md` - Technical details
- `TESTING_GUIDE.md` - Comprehensive testing procedures