#!/bin/bash

# Test script for resource validation functionality

echo "Resource Validation Test Script"
echo "=============================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base URL
BASE_URL="http://localhost:8080"

# Get CSRF token
echo "1. Getting CSRF token..."
CSRF_RESPONSE=$(curl -s -c cookies.txt "$BASE_URL/api/csrf-token")
CSRF_TOKEN=$(echo $CSRF_RESPONSE | jq -r '.token')

if [ -z "$CSRF_TOKEN" ] || [ "$CSRF_TOKEN" = "null" ]; then
  echo -e "${RED}✗ Failed to get CSRF token${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Got CSRF token${NC}"

# Test pre-flight checks endpoint
echo ""
echo "2. Testing pre-flight checks endpoint..."
PREFLIGHT_RESPONSE=$(curl -s -b cookies.txt -H "X-CSRF-Token: $CSRF_TOKEN" "$BASE_URL/api/preflight")

if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to call pre-flight endpoint${NC}"
  exit 1
fi

# Parse response
PASSED=$(echo $PREFLIGHT_RESPONSE | jq -r '.passed')
DURATION=$(echo $PREFLIGHT_RESPONSE | jq -r '.duration')
MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.summary.message')

echo ""
echo "Pre-flight Check Results:"
echo "========================"
echo -e "Overall Status: $([ "$PASSED" = "true" ] && echo "${GREEN}PASSED${NC}" || echo "${RED}FAILED${NC}")"
echo -e "Duration: ${DURATION}ms"
echo -e "Message: $MESSAGE"

# Individual checks
echo ""
echo "Individual Checks:"
echo "------------------"

# Disk space
DISK_SUFFICIENT=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.disk.sufficient')
DISK_MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.disk.message')
echo -e "Disk Space: $([ "$DISK_SUFFICIENT" = "true" ] && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}") $DISK_MESSAGE"

# Memory
MEMORY_SUFFICIENT=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.memory.sufficient')
MEMORY_MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.memory.message')
echo -e "Memory: $([ "$MEMORY_SUFFICIENT" = "true" ] && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}") $MEMORY_MESSAGE"

# Docker
DOCKER_AVAILABLE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.docker.available')
DOCKER_MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.docker.message')
echo -e "Docker: $([ "$DOCKER_AVAILABLE" = "true" ] && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}") $DOCKER_MESSAGE"

# Network
NETWORK_CRITICAL=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.network.criticalAccessible')
NETWORK_MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.network.message')
echo -e "Network: $([ "$NETWORK_CRITICAL" = "true" ] && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}") $NETWORK_MESSAGE"

# Ports
PORTS_AVAILABLE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.ports.available')
PORTS_MESSAGE=$(echo $PREFLIGHT_RESPONSE | jq -r '.checks.ports.message')
echo -e "Ports: $([ "$PORTS_AVAILABLE" = "true" ] && echo "${GREEN}✓${NC}" || echo "${YELLOW}⚠${NC}") $PORTS_MESSAGE"

# Show critical issues if any
CRITICAL_ISSUES=$(echo $PREFLIGHT_RESPONSE | jq -r '.summary.criticalIssues[]?' 2>/dev/null)
if [ ! -z "$CRITICAL_ISSUES" ]; then
  echo ""
  echo -e "${RED}Critical Issues:${NC}"
  echo "$CRITICAL_ISSUES" | while read -r issue; do
    echo "  - $issue"
  done
fi

# Show warnings if any
WARNINGS=$(echo $PREFLIGHT_RESPONSE | jq -r '.summary.warnings[]?' 2>/dev/null)
if [ ! -z "$WARNINGS" ]; then
  echo ""
  echo -e "${YELLOW}Warnings:${NC}"
  echo "$WARNINGS" | while read -r warning; do
    echo "  - $warning"
  done
fi

# Test deployment with pre-flight checks
echo ""
echo ""
echo "3. Testing deployment with pre-flight checks..."
echo "Note: This will trigger pre-flight checks before deployment"

# Prepare deployment config
DEPLOY_CONFIG=$(cat <<EOF
{
  "adminEmail": "test@example.com",
  "adminPassword": "SecurePass123!",
  "domain": "localhost",
  "sslProvider": "none",
  "edition": "community",
  "enableMfa": false,
  "enableAudit": true,
  "enableBackups": true
}
EOF
)

# Start deployment (which should run pre-flight checks first)
echo "Starting deployment..."
DEPLOY_RESPONSE=$(curl -s -X POST \
  -b cookies.txt \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -d "$DEPLOY_CONFIG" \
  "$BASE_URL/api/deploy")

DEPLOYMENT_ID=$(echo $DEPLOY_RESPONSE | jq -r '.deploymentId')

if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "null" ]; then
  echo -e "${RED}✗ Failed to start deployment${NC}"
  ERROR=$(echo $DEPLOY_RESPONSE | jq -r '.error // "Unknown error"')
  echo "Error: $ERROR"
  
  # Check if it's due to pre-flight checks
  if [[ "$ERROR" == *"Pre-flight checks failed"* ]]; then
    echo -e "${YELLOW}This is expected if system resources are insufficient${NC}"
  fi
else
  echo -e "${GREEN}✓ Deployment started with ID: $DEPLOYMENT_ID${NC}"
  echo "Pre-flight checks passed and deployment is proceeding"
fi

# Clean up
rm -f cookies.txt

echo ""
echo "Test completed!"