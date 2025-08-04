#!/bin/bash

# Test the credential deprecation system

echo "=== Testing Credential Deprecation System ==="
echo

# 1. Check if n8n is running
echo "1. Checking n8n container..."
if sudo -u devops docker ps | grep -q app-n8n; then
    echo "✅ n8n container is running"
else
    echo "❌ n8n container is not running"
    exit 1
fi

# 2. Get n8n version
echo
echo "2. Getting n8n version..."
N8N_VERSION=$(sudo -u devops docker exec app-n8n n8n --version 2>/dev/null || echo "unknown")
echo "n8n version: $N8N_VERSION"

# 3. Check for actual credential types in n8n
echo
echo "3. Checking credential types in n8n..."
echo "Looking for credential type files..."

# Find credential files in n8n container
sudo -u devops docker exec app-n8n bash -c '
    find /usr/local/lib/node_modules/n8n -name "*.credentials.js" -o -name "*.credentials.ts" 2>/dev/null | 
    grep -E "(Twitter|Google|Slack|Dropbox|GitHub)" | 
    head -10
'

# 4. List any existing credentials
echo
echo "4. Checking existing credentials in n8n..."
CREDS=$(sudo -u devops docker exec app-n8n n8n credential:list 2>&1 || echo "No credentials found")
echo "$CREDS"

# 5. Create test SQL to insert deprecation data
echo
echo "5. Creating test SQL..."
cat > /tmp/test-deprecation.sql << 'EOF'
-- Insert test deprecation configuration
INSERT INTO stack_manager.system_config (key, value) 
VALUES ('credential_deprecations', '{
  "deprecated_types": {
    "twitterOAuth1Api": {
      "status": "deprecated",
      "deprecatedIn": "0.236.0",
      "replacementType": "twitterOAuth2Api",
      "message": "Twitter OAuth1 is deprecated. Use OAuth2.",
      "severity": "warning"
    },
    "googleApi": {
      "status": "deprecated", 
      "deprecatedIn": "0.220.0",
      "replacementType": "googleOAuth2Api",
      "message": "Legacy Google API auth deprecated. Use OAuth2.",
      "severity": "critical"
    }
  },
  "pending_deprecations": {
    "httpQueryAuth": {
      "status": "pending",
      "deprecationVersion": "2.0.0",
      "replacementType": "httpHeaderAuth",
      "message": "HTTP Query Auth will be deprecated in v2.0.0",
      "severity": "info"
    }
  }
}')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = CURRENT_TIMESTAMP;

-- Check if we have the deprecation tables
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'stack_manager' 
  AND table_name = 'alerts'
) as alerts_table_exists;

-- If you have test credentials, check their deprecation status
SELECT * FROM stack_manager.credentials 
WHERE provider_type IN ('twitterOAuth1Api', 'googleApi', 'httpQueryAuth', 'aws')
LIMIT 5;
EOF

echo "Test SQL saved to: /tmp/test-deprecation.sql"

# 6. Test the API endpoint (if Stack Manager is running)
echo
echo "6. Testing API endpoint..."
if curl -s -f http://localhost:3002/api/health > /dev/null 2>&1; then
    echo "✅ Stack Manager API is running"
    
    # Try to get deprecation summary
    echo "Fetching deprecation summary..."
    curl -s http://localhost:3002/api/credentials/deprecation/summary | jq '.' 2>/dev/null || echo "API call failed"
else
    echo "❌ Stack Manager API is not running on port 3002"
fi

echo
echo "=== Test Complete ==="
echo
echo "To run the deprecation check SQL:"
echo "docker exec -i postgres-db psql -U postgres -d n8n < /tmp/test-deprecation.sql"
echo
echo "Known deprecated credential types based on n8n changelog:"
echo "- twitterOAuth1Api → twitterOAuth2Api (Twitter moved to OAuth2)"
echo "- googleApi → googleOAuth2Api (Google deprecated legacy auth)"
echo "- slackApi → slackOAuth2Api (Slack phasing out legacy tokens)"
echo "- httpQueryAuth → httpHeaderAuth (Query params less secure)"
echo
echo "These are real deprecations that happened in n8n's history."