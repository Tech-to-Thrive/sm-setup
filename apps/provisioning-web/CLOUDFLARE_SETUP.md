# Cloudflare Integration Setup Guide

## Overview
The AI Stack Master provisioning app supports two Cloudflare integration methods:
1. **Cloudflare Tunnel** (Recommended) - Zero-trust secure tunnel to your services
2. **Cloudflare API** - Direct DNS management for traditional SSL

## Required Permissions

### API Token Permissions
Create a **Custom API Token** with these permissions:

| Permission | Level | Purpose |
|------------|-------|---------|
| `Zone:Zone:Read` | Read | List and identify zones |
| `Zone:DNS:Edit` | Edit | Create/modify DNS records |
| `Account:Cloudflare Tunnel:Edit` | Edit | Create and manage tunnels (Tunnel mode only) |

### Zone Resources
- **Include**: Specific zone → Your domain
- **Or**: All zones (less secure)

## Step-by-Step Setup

### 1. Create API Token
1. Navigate to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **"Create Token"**
3. Select **"Custom token"** template
4. Configure permissions as listed above
5. Set **Zone Resources** to your specific domain
6. Optional: Set token expiration for added security
7. Click **"Continue to summary"** → **"Create Token"**
8. **IMPORTANT**: Copy the token immediately (shown only once)

### 2. Find Account ID
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Look in the right sidebar under **"API"** section
4. Copy the **Account ID** (32-character string)

### 3. Find Zone ID (Optional)
- Located in the same sidebar as Account ID
- The provisioning app can auto-detect this from Account ID

## Security Best Practices

### Use API Tokens (Not Global API Key)
- ✅ API Tokens have scoped permissions
- ✅ Can be limited to specific zones
- ✅ Can have expiration dates
- ❌ Global API Key has full account access

### Token Security
1. **Never commit tokens to git**
2. **Store securely** (password manager)
3. **Rotate regularly**
4. **Use minimum required permissions**

### Cloudflare Tunnel Benefits
- No port forwarding required
- No public IP exposure
- Built-in DDoS protection
- Automatic SSL certificates
- Zero-trust security model

## Troubleshooting

### Common Issues

#### "Invalid API Token"
- Verify token was copied correctly (no spaces)
- Check token hasn't expired
- Ensure token has required permissions

#### "Zone not found"
- Verify domain is added to Cloudflare account
- Check Account ID is correct
- Ensure token has access to the zone

#### "Permission denied"
- Token missing required permissions
- Zone resources not configured correctly
- Using Global API Key instead of API Token

### Testing Your Token
```bash
# Test token validity
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer YOUR_API_TOKEN" \
     -H "Content-Type: application/json"

# List zones (verify access)
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
     -H "Authorization: Bearer YOUR_API_TOKEN" \
     -H "Content-Type: application/json"
```

## Integration Modes

### Cloudflare Tunnel Mode
Best for:
- Home servers without static IP
- Services behind NAT/firewall
- Maximum security requirements

Features:
- Creates secure outbound-only tunnel
- No inbound ports required
- Automatic SSL certificates
- Built-in web application firewall

### Cloudflare API Mode
Best for:
- Servers with public IP
- Traditional SSL setup
- Custom certificate management

Features:
- Creates DNS A/CNAME records
- Works with Let's Encrypt
- More control over SSL configuration
- Compatible with existing setups

## Post-Deployment

After successful deployment with Cloudflare:

1. **Verify DNS Records**
   - Check Cloudflare dashboard for new records
   - Test DNS resolution: `nslookup your-domain.com`

2. **Test SSL Certificate**
   - Visit `https://your-domain.com`
   - Check certificate details in browser

3. **Monitor Tunnel Status** (Tunnel mode)
   - View in Cloudflare Zero Trust dashboard
   - Check tunnel health and metrics

4. **Configure Firewall Rules** (Optional)
   - Add Web Application Firewall rules
   - Set up rate limiting
   - Configure bot protection

## Support Resources

- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [API Token Permissions](https://developers.cloudflare.com/api/tokens/create/permissions/)
- [Cloudflare Community](https://community.cloudflare.com/)

## Security Checklist

- [ ] Using API Token (not Global API Key)
- [ ] Token has minimum required permissions
- [ ] Token limited to specific zones
- [ ] Token stored securely
- [ ] Account has 2FA enabled
- [ ] Cloudflare account email verified
- [ ] API token has expiration date (optional)
- [ ] Backup authentication method configured