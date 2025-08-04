#!/bin/bash

echo "Testing Deployment Lock Mechanism"
echo "================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Get token
TOKEN=$(grep "Token:" server.log | grep -v "║" | tail -1 | awk '{print $3}' | sed 's/║//g' | tr -d ' ')
if [ -z "$TOKEN" ]; then
  TOKEN=$(grep -oP '(?<=Token: )[a-f0-9]{32}' server.log | tail -1)
fi

BASE_URL="http://localhost:8080"

echo "Using token: $TOKEN"
echo ""

# Get CSRF token
CSRF_TOKEN=$(curl -s -c cookies.txt "$BASE_URL/api/csrf-token?token=$TOKEN" | jq -r .token)

# Test 1: Check initial lock status
echo -n "1. Initial lock status: "
LOCK_STATUS=$(curl -s -b cookies.txt "$BASE_URL/api/deployment/lock-status?token=$TOKEN")
LOCKED=$(echo "$LOCK_STATUS" | jq -r .locked)
if [ "$LOCKED" = "false" ]; then
  echo -e "${GREEN}✓ Not locked${NC}"
else
  echo -e "${RED}✗ Lock should not be active${NC}"
  echo "$LOCK_STATUS" | jq
fi

echo ""

# Test 2: Start first deployment
echo "2. Starting first deployment..."
DEPLOY1=$(curl -s -b cookies.txt -X POST "$BASE_URL/api/deploy" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -d '{"domain": "test1.local", "adminEmail": "admin@test1.local"}' &)

# Give it a moment to acquire lock
sleep 2

# Test 3: Check lock status during deployment
echo -n "3. Lock status during deployment: "
LOCK_STATUS=$(curl -s -b cookies.txt "$BASE_URL/api/deployment/lock-status?token=$TOKEN")
LOCKED=$(echo "$LOCK_STATUS" | jq -r .locked)
PID=$(echo "$LOCK_STATUS" | jq -r .pid)
if [ "$LOCKED" = "true" ] && [ "$PID" != "null" ]; then
  echo -e "${GREEN}✓ Locked (PID: $PID)${NC}"
else
  echo -e "${RED}✗ Lock should be active${NC}"
  echo "$LOCK_STATUS" | jq
fi

echo ""

# Test 4: Try concurrent deployment (should fail)
echo -n "4. Attempting concurrent deployment: "
DEPLOY2=$(curl -s -b cookies.txt -X POST "$BASE_URL/api/deploy" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -d '{"domain": "test2.local", "adminEmail": "admin@test2.local"}' \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$DEPLOY2" | tail -1)
RESPONSE=$(echo "$DEPLOY2" | head -n -1)

if [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "409" ]; then
  echo -e "${GREEN}✓ Blocked concurrent deployment${NC}"
elif echo "$RESPONSE" | grep -q "already in progress"; then
  echo -e "${GREEN}✓ Blocked (deployment already in progress)${NC}"
else
  echo -e "${RED}✗ Should have blocked concurrent deployment${NC}"
  echo "Response: $RESPONSE"
fi

echo ""

# Test 5: Force unlock (simulate cleanup)
echo -n "5. Testing force unlock: "
# This would normally be done internally - just checking the API
sleep 1
echo -e "${YELLOW}⚠ Manual unlock not exposed via API (by design)${NC}"

echo ""
echo "Deployment lock testing complete!"
echo ""
echo "Note: The first deployment may still be running in background."
echo "Check 'docker ps' to see if containers are being created."