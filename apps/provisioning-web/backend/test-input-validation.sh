#!/bin/bash

echo "Testing Input Validation Middleware"
echo "==================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Get token from server
TOKEN=$(grep "Token:" server.log | grep -v "║" | tail -1 | awk '{print $3}' | sed 's/║//g' | tr -d ' ')
if [ -z "$TOKEN" ]; then
  TOKEN=$(grep -oP '(?<=Token: )[a-f0-9]{32}' server.log | tail -1)
fi

BASE_URL="http://localhost:8080"

echo "Using token: $TOKEN"
echo ""

# Test 1: Command injection attempts
echo "1. Testing command injection protection:"

# Test 1a: Shell command injection
echo -n "   a) Shell command injection: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"domain": "example.com; cat /etc/passwd"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ] && echo "$RESPONSE" | grep -q "DANGEROUS_INPUT"; then
  echo -e "${GREEN}✓ Blocked (400 - DANGEROUS_INPUT)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

# Test 1b: Backtick command injection
echo -n "   b) Backtick injection: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"domain": "example.com`whoami`"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

# Test 1c: Variable expansion
echo -n "   c) Variable expansion: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"domain": "example.com${PATH}"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""

# Test 2: SQL injection attempts
echo "2. Testing SQL injection protection:"

echo -n "   a) SQL injection: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"adminEmail": "admin@test.com\" OR \"1\"=\"1"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""

# Test 3: Path traversal attempts
echo "3. Testing path traversal protection:"

echo -n "   a) Path traversal: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"domain": "../../../etc/passwd"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""

# Test 4: XSS attempts
echo "4. Testing XSS protection:"

echo -n "   a) Script tag injection: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"adminName": "<script>alert(1)</script>"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""

# Get CSRF token first
CSRF_TOKEN=$(curl -s -c cookies.txt "$BASE_URL/api/csrf-token?token=$TOKEN" | jq -r .token)

# Test 5: Valid inputs
echo "5. Testing valid inputs (should pass):"

echo -n "   a) Valid domain: "
RESPONSE=$(curl -s -b cookies.txt -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -d '{"domain": "example.com"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Allowed (200)${NC}"
else
  echo -e "${RED}✗ BLOCKED - Expected 200, got $HTTP_CODE${NC}"
  echo "$RESPONSE" | head -n -1
fi

echo -n "   b) Valid email: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"adminEmail": "admin@example.com", "domain": "example.com"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Allowed (200)${NC}"
else
  echo -e "${RED}✗ BLOCKED - Expected 200, got $HTTP_CODE${NC}"
fi

echo ""

# Test 6: Length limits
echo "6. Testing length limits:"

echo -n "   a) Oversized domain (300 chars): "
LONG_DOMAIN=$(python3 -c "print('a' * 300 + '.com')")
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d "{\"domain\": \"$LONG_DOMAIN\"}" \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ] && echo "$RESPONSE" | grep -q "INPUT_TOO_LONG"; then
  echo -e "${GREEN}✓ Blocked (400 - INPUT_TOO_LONG)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""

# Test 7: Special characters in different fields
echo "7. Testing special character blocking:"

echo -n "   a) Pipe character in domain: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate/domain" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d '{"domain": "example.com|whoami"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo -n "   b) Null byte injection: "
RESPONSE=$(curl -s -X POST "$BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -H "X-Setup-Token: $TOKEN" \
  -d $'{"domain": "example.com\\x00.evil.com"}' \
  -w "\n%{http_code}")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "400" ]; then
  echo -e "${GREEN}✓ Blocked (400)${NC}"
else
  echo -e "${RED}✗ NOT BLOCKED - Expected 400, got $HTTP_CODE${NC}"
fi

echo ""
echo "Input validation testing complete!"
echo ""

# Summary
echo "Note: All dangerous inputs should be blocked with 400 status."
echo "Valid inputs should pass with 200 status."