#!/bin/bash

echo "Testing Provisioning Security..."
echo "================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test URL
BASE_URL="http://localhost:8080"

# Test 1: Access without token
echo -n "1. Testing access without token: "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/api/validate)
if [ "$RESPONSE" = "401" ]; then
  echo -e "${GREEN}✓ Blocked (401)${NC}"
else
  echo -e "${RED}✗ FAILED - Expected 401, got $RESPONSE${NC}"
fi

# Test 2: Access with invalid token
echo -n "2. Testing access with invalid token: "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/validate?token=invalid")
if [ "$RESPONSE" = "401" ]; then
  echo -e "${GREEN}✓ Blocked (401)${NC}"
else
  echo -e "${RED}✗ FAILED - Expected 401, got $RESPONSE${NC}"
fi

# Test 3: CSRF protection
echo -n "3. Testing CSRF protection: "
RESPONSE=$(curl -s -X POST -o /dev/null -w "%{http_code}" $BASE_URL/api/deploy)
if [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "403" ]; then
  echo -e "${GREEN}✓ Protected ($RESPONSE)${NC}"
else
  echo -e "${RED}✗ FAILED - Expected 401/403, got $RESPONSE${NC}"
fi

# Test 4: Rate limiting (optional - takes time)
if [ "$1" = "--full" ]; then
  echo -n "4. Testing rate limiting (sending 60 requests): "
  for i in {1..60}; do
    curl -s $BASE_URL/api/validate > /dev/null 2>&1
  done
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/api/validate)
  if [ "$RESPONSE" = "429" ]; then
    echo -e "${GREEN}✓ Rate limited (429)${NC}"
  else
    echo -e "${RED}✗ FAILED - Expected 429, got $RESPONSE${NC}"
  fi
else
  echo "4. Skipping rate limit test (use --full to enable)"
fi

# Test 5: Welcome page
echo -n "5. Testing welcome page: "
CONTENT=$(curl -s $BASE_URL/)
if echo "$CONTENT" | grep -q "Setup Required"; then
  echo -e "${GREEN}✓ Welcome page shown${NC}"
else
  echo -e "${RED}✗ FAILED - Welcome page not shown${NC}"
fi

echo ""
echo "Testing complete!"