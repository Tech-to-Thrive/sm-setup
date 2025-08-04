# Complete Cloudflare Setup Guide for AI Stack Master

This guide covers all aspects of Cloudflare integration, including detailed permissions, setup steps, and troubleshooting.

## Table of Contents

1. [Cloudflare Integration Options](#cloudflare-integration-options)
2. [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
3. [Cloudflare API Setup](#cloudflare-api-setup)
4. [Permission Requirements](#permission-requirements)
5. [Common Issues & Solutions](#common-issues--solutions)
6. [Security Best Practices](#security-best-practices)
7. [Supporting Articles](#supporting-articles)

## Cloudflare Integration Options

### 1. Cloudflare Tunnel (Recommended for Pro/Enterprise)

**Benefits:**
- ✅ No inbound ports required
- ✅ Built-in DDoS protection
- ✅ Automatic SSL/TLS certificates
- ✅ Global edge network
- ✅ Zero-trust security model
- ✅ Access policies and authentication

**Best For:**
- Production deployments
- Security-conscious organizations
- Multi-service architectures
- Teams requiring access control

### 2. Cloudflare API (Traditional DNS)

**Benefits:**
- ✅ Full DNS control
- ✅ Programmatic updates
- ✅ Multiple record types
- ✅ Works with existing infrastructure
- ✅ Familiar DNS management

**Best For:**
- Teams with existing DNS workflows
- Simple deployments
- Development environments
- Custom DNS requirements

## Cloudflare Tunnel Setup

### Step 1: Access Cloudflare One Dashboard

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Navigate to **Zero Trust** (formerly Cloudflare for Teams)
4. Go to [one.dash.cloudflare.com](https://one.dash.cloudflare.com)

### Step 2: Create a Tunnel

1. Navigate to **Access** → **Tunnels**
2. Click **Create a tunnel**
3. Name your tunnel (e.g., `ai-stack-master-prod`)
4. Save the tunnel

### Step 3: Configure the Tunnel

1. **Install and run a connector** section will appear
2. Choose **Docker** as your environment
3. Copy the provided token (starts with `eyJ...`)
4. This token includes ALL necessary permissions

### Step 4: Configure Public Hostnames

After creating the tunnel, configure hostnames:

1. Click **Configure** on your tunnel
2. Add public hostnames:
   ```
   Service: HTTP
   URL: stack-manager:3002
   Hostname: stack.yourdomain.com
   
   Service: HTTP
   URL: grafana:3000
   Hostname: grafana.yourdomain.com
   
   Service: HTTP
   URL: n8n:5678
   Hostname: n8n.yourdomain.com
   
   Service: HTTP
   URL: prometheus:9090
   Hostname: metrics.yourdomain.com
   ```

### Step 5: Advanced Configuration

For enterprise features:

1. **Access Policies**: Set up authentication requirements
2. **Browser Rendering**: Enable for n8n UI
3. **Load Balancing**: Configure multiple origins
4. **Health Checks**: Monitor service availability

## Cloudflare API Setup

### Step 1: Create API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use **Custom token** template

### Step 2: Configure Permissions

Add these specific permissions:

```yaml
Permissions:
  Zone:
    - Zone:Read
    - DNS:Read
    - DNS:Edit
    - SSL and Certificates:Read
    
  Account (optional for advanced features):
    - Cloudflare Tunnel:Read
    - Cloudflare Tunnel:Edit
    - Access: Apps and Policies:Read
    - Access: Apps and Policies:Edit
```

### Step 3: Zone Resources

- **Specific zone**: Select your domain
- **Include**: All zones (if managing multiple domains)

### Step 4: IP Filtering (Optional)

For additional security, restrict token to your server IPs:
- Add your server's public IP
- Add your local development IP (if needed)

### Step 5: TTL Settings

- Set appropriate TTL (Time to Live)
- Recommendation: 1 year for production
- Note: Tokens can be rotated anytime

## Permission Requirements

### Cloudflare Tunnel Permissions

The tunnel token automatically includes:

```yaml
Included Permissions:
  - Tunnel:Read (View tunnel configuration)
  - Tunnel:Write (Update tunnel configuration)
  - Account:Read (List account resources)
  - DNS:Write (Create DNS records for tunnel)
  - Certificate:Write (Issue certificates)
```

### Cloudflare API Permissions

For full functionality:

```yaml
Required Permissions:
  Zone Level:
    - Zone:Read (View zone details)
    - DNS:Read (List DNS records)
    - DNS:Edit (Create/update/delete records)
    - SSL and Certificates:Read (View SSL status)
    
  Optional Advanced:
    - Analytics:Read (View traffic analytics)
    - Firewall:Read (View security rules)
    - Firewall:Edit (Manage security rules)
    - Cache Purge:Purge (Clear cache)
```

## Common Issues & Solutions

### 1. "Invalid API Token" Error

**Symptoms:**
- 401 Unauthorized errors
- "Invalid token" messages

**Solutions:**
1. Verify token permissions match requirements
2. Check token hasn't expired
3. Ensure no extra spaces when pasting
4. Verify zone ID is correct

### 2. "Tunnel Connection Failed"

**Symptoms:**
- Tunnel shows as "Inactive"
- Services unreachable

**Solutions:**
1. Check Docker container logs: `docker logs cloudflared`
2. Verify network connectivity
3. Ensure tunnel token is valid
4. Check firewall allows outbound 443

### 3. "DNS Record Conflict"

**Symptoms:**
- "Record already exists" errors
- Conflicting A/CNAME records

**Solutions:**
1. Remove existing DNS records first
2. Use different subdomains
3. Enable "Proxy" status for security

### 4. "SSL Certificate Issues"

**Symptoms:**
- Browser warnings
- Certificate errors

**Solutions:**
1. Enable "Full (Strict)" SSL mode
2. Wait for certificate propagation (5-10 minutes)
3. Clear browser cache
4. Check origin certificate validity

## Security Best Practices

### 1. Token Management

```bash
# Store tokens securely
export CLOUDFLARE_API_TOKEN="your-token"
export CLOUDFLARE_TUNNEL_TOKEN="your-tunnel-token"

# Never commit tokens to git
echo "CLOUDFLARE_*" >> .gitignore
```

### 2. Access Policies (Tunnel)

Configure Zero Trust policies:

```yaml
Access Policies:
  - Name: "Admin Access"
    Include:
      - Emails: ["admin@company.com"]
      - IP Ranges: ["10.0.0.0/8"]
    Require:
      - Purpose: "Administrative access"
      - MFA: true
```

### 3. Rate Limiting

Protect your services:

```yaml
Rate Limiting Rules:
  - Endpoint: "/api/*"
    Threshold: 100 requests per minute
    Action: Challenge
    
  - Endpoint: "/login"
    Threshold: 5 requests per minute
    Action: Block for 1 hour
```

### 4. WAF Rules

Enable Web Application Firewall:

```yaml
WAF Custom Rules:
  - Name: "Block SQL Injection"
    Expression: (http.request.uri.query contains "union select")
    Action: Block
    
  - Name: "Protect Admin"
    Expression: (http.request.uri.path contains "/admin")
    Action: Challenge
```

## Supporting Articles

### Official Cloudflare Documentation

1. **Cloudflare Tunnel**
   - [Getting Started with Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
   - [Tunnel Configuration Guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/)
   - [Tunnel Best Practices](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/best-practices/)
   - [Troubleshooting Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/troubleshooting/)

2. **API Documentation**
   - [API Authentication](https://developers.cloudflare.com/api/tokens/)
   - [DNS Record Management](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records)
   - [API Best Practices](https://developers.cloudflare.com/api/best-practices/)
   - [Rate Limits](https://developers.cloudflare.com/api/rate-limits/)

3. **Security Features**
   - [Zero Trust Overview](https://developers.cloudflare.com/cloudflare-one/)
   - [Access Policies](https://developers.cloudflare.com/cloudflare-one/policies/access/)
   - [WAF Custom Rules](https://developers.cloudflare.com/waf/custom-rules/)
   - [DDoS Protection](https://developers.cloudflare.com/ddos-protection/)

### Video Tutorials

1. **Cloudflare Tunnel Setup**
   - [Official Cloudflare Tunnel Tutorial](https://www.youtube.com/watch?v=RQ45r0Ogs8I)
   - [Docker Integration Guide](https://www.youtube.com/watch?v=ZvIdvgURnPg)

2. **API Configuration**
   - [Creating API Tokens](https://www.youtube.com/watch?v=QzG6L8pzfI0)
   - [DNS Automation](https://www.youtube.com/watch?v=XQKkb-5HMS8)

### Community Resources

1. **Forums & Support**
   - [Cloudflare Community](https://community.cloudflare.com/)
   - [Stack Overflow - Cloudflare Tag](https://stackoverflow.com/questions/tagged/cloudflare)
   - [Reddit r/CloudFlare](https://www.reddit.com/r/CloudFlare/)

2. **Blog Articles**
   - [Cloudflare Blog - Tunnel Announcements](https://blog.cloudflare.com/tunnel-for-everyone/)
   - [Zero Trust Architecture Guide](https://blog.cloudflare.com/zero-trust-architecture/)
   - [API Security Best Practices](https://blog.cloudflare.com/api-security-best-practices/)

### Integration Examples

1. **Docker Compose Integration**
   ```yaml
   services:
     cloudflared:
       image: cloudflare/cloudflared:latest
       command: tunnel run
       environment:
         - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
       restart: unless-stopped
       networks:
         - ai-stack-network
   ```

2. **API Script Examples**
   - [DNS Update Script](https://github.com/cloudflare/cloudflare-docs/tree/main/examples/dns-update)
   - [Bulk DNS Management](https://github.com/cloudflare/cloudflare-docs/tree/main/examples/bulk-dns)
   - [Certificate Management](https://github.com/cloudflare/cloudflare-docs/tree/main/examples/certificates)

### Troubleshooting Resources

1. **Status & Monitoring**
   - [Cloudflare System Status](https://www.cloudflarestatus.com/)
   - [Network Map](https://www.cloudflare.com/network/)
   - [Speed Test](https://speed.cloudflare.com/)

2. **Debug Tools**
   - [DNS Checker](https://www.cloudflare.com/lp/dns-lookup-tool/)
   - [Trace Route](https://www.cloudflare.com/cdn-cgi/trace)
   - [SSL Test](https://www.ssllabs.com/ssltest/)

## Quick Reference

### Environment Variables

```bash
# Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=eyJ...

# Cloudflare API
CLOUDFLARE_API_TOKEN=your-api-token
CLOUDFLARE_ZONE_ID=your-zone-id
CLOUDFLARE_ACCOUNT_ID=your-account-id

# Optional
CLOUDFLARE_TUNNEL_METRICS_PORT=9090
CLOUDFLARE_TUNNEL_LOGLEVEL=info
```

### Useful Commands

```bash
# Test API token
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer YOUR_API_TOKEN"

# List DNS records
curl -X GET "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
     -H "Authorization: Bearer YOUR_API_TOKEN"

# Check tunnel status
docker logs cloudflared

# Restart tunnel
docker restart cloudflared
```

### Port Reference

| Service | Internal Port | Cloudflare Route |
|---------|--------------|------------------|
| Stack Manager UI | 3001 | stack.domain.com |
| Stack Manager API | 3002 | api.domain.com |
| Grafana | 3000 | grafana.domain.com |
| n8n | 5678 | n8n.domain.com |
| Prometheus | 9090 | metrics.domain.com |

## Getting Help

1. **AI Stack Master Community**
   - Community Edition: https://www.skool.com/ai-stack-masters
   - Pro/Enterprise: https://www.skool.com/ai-stack-master-pros

2. **Cloudflare Support**
   - Free Plan: Community forums
   - Pro Plan: Email support
   - Enterprise: Dedicated support team

3. **Emergency Contacts**
   - Security Issues: security@cloudflare.com
   - Abuse Reports: abuse@cloudflare.com

---

Last Updated: 2025-07-10
Version: 2.0.0