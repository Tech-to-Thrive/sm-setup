#!/bin/bash

echo "Complete Security Test Suite"
echo "==========================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Get token from server log
TOKEN=$(grep "Token:" server.log | grep -v "║" | tail -1 | awk '{print $3}' | sed 's/║//g' | tr -d ' ')
if [ -z "$TOKEN" ]; then
  TOKEN=$(grep -oP '(?<=Token: )[a-f0-9]{32}' server.log | tail -1)
fi

echo "Using token: $TOKEN"
echo ""

# Test 1: Access without token (should be blocked)
echo -n "1. Access API without token: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Health check accessible${NC}"
else
  echo -e "${RED}✗ Health check blocked (got $HTTP_CODE)${NC}"
fi

# Test 2: Welcome page without token
echo -n "2. Welcome page without token: "
CONTENT=$(curl -s http://localhost:8080/)
if echo "$CONTENT" | grep -q "Setup Required"; then
  echo -e "${GREEN}✓ Welcome page shown${NC}"
else
  echo -e "${RED}✗ Welcome page not shown${NC}"
fi

# Test 3: Access with invalid token
echo -n "3. Access with invalid token: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/domain?token=invalid")
if [ "$HTTP_CODE" = "401" ]; then
  echo -e "${GREEN}✓ Blocked (401)${NC}"
else
  echo -e "${RED}✗ Expected 401, got $HTTP_CODE${NC}"
fi

# Test 4: Access with valid token
echo -n "4. Access with valid token: "
rm -f cookies.txt
RESPONSE=$(curl -s -c cookies.txt -w "\n%{http_code}" "http://localhost:8080/?token=$TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Access granted (200)${NC}"
else
  echo -e "${RED}✗ Expected 200, got $HTTP_CODE${NC}"
fi

# Test 5: Check cookies were set
echo -n "5. Authentication cookies set: "
if grep -q "setupToken" cookies.txt && grep -q "csrfToken" cookies.txt; then
  echo -e "${GREEN}✓ Both cookies set${NC}"
else
  echo -e "${RED}✗ Cookies not properly set${NC}"
  cat cookies.txt
fi

# Test 6: Access API with cookie
echo -n "6. API access with cookie: "
CSRF_RESPONSE=$(curl -s -b cookies.txt http://localhost:8080/api/csrf-token)
if echo "$CSRF_RESPONSE" | grep -q "token"; then
  echo -e "${GREEN}✓ API accessible with cookie${NC}"
else
  echo -e "${RED}✗ API not accessible${NC}"
fi

# Test 7: CSRF protection
echo -n "7. CSRF protection on POST: "
HTTP_CODE=$(curl -s -X POST -b cookies.txt -o /dev/null -w "%{http_code}" http://localhost:8080/api/deploy)
if [ "$HTTP_CODE" = "403" ]; then
  echo -e "${GREEN}✓ CSRF protection active (403)${NC}"
else
  echo -e "${RED}✗ Expected 403, got $HTTP_CODE${NC}"
fi

# Test 8: POST with CSRF token
echo -n "8. POST with CSRF token: "
CSRF_TOKEN=$(curl -s -b cookies.txt http://localhost:8080/api/csrf-token | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
HTTP_CODE=$(curl -s -X POST -b cookies.txt -H "X-CSRF-Token: $CSRF_TOKEN" -H "Content-Type: application/json" -d '{"test": true}' -o /dev/null -w "%{http_code}" http://localhost:8080/api/validate/domain)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ CSRF token accepted${NC}"
else
  echo -e "${RED}✗ Unexpected response: $HTTP_CODE${NC}"
fi

# Test 9: Security headers
echo -n "9. Security headers present: "
HEADERS=$(curl -s -I -b cookies.txt http://localhost:8080/)
if echo "$HEADERS" | grep -q "X-Content-Type-Options" && echo "$HEADERS" | grep -q "X-Frame-Options"; then
  echo -e "${GREEN}✓ Security headers present${NC}"
else
  echo -e "${RED}✗ Security headers missing${NC}"
fi

# Test 10: Rate limiting (optional)
if [ "$1" = "--full" ]; then
  echo -n "10. Rate limiting test: "
  # Send 60 requests rapidly
  for i in {1..60}; do
    curl -s http://localhost:8080/api/health > /dev/null 2>&1 &
  done
  wait
  sleep 1
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health)
  if [ "$HTTP_CODE" = "429" ]; then
    echo -e "${GREEN}✓ Rate limiting active (429)${NC}"
  else
    echo -e "${YELLOW}⚠ Rate limiting may not be active (got $HTTP_CODE)${NC}"
  fi
else
  echo "10. Rate limiting: Skipped (use --full to test)"
fi

echo ""
echo "Security test complete!"
echo ""

# Cleanup
rm -f cookies.txt