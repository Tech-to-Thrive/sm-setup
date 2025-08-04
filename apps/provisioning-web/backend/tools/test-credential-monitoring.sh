#!/bin/bash

# Test Credential Monitoring System
# Tests the automated credential type monitoring and hint generation system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_MANAGER_API="http://localhost:3002"
TEST_TIMEOUT=30

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to make API calls with authentication
api_call() {
    local method=$1
    local endpoint=$2
    local data=${3:-""}
    
    if [ -z "$AUTH_TOKEN" ]; then
        print_error "AUTH_TOKEN not set. Please authenticate first."
        return 1
    fi
    
    local curl_opts="-s -X $method -H 'Authorization: Bearer $AUTH_TOKEN' -H 'Content-Type: application/json'"
    
    if [ -n "$data" ]; then
        curl_opts="$curl_opts -d '$data'"
    fi
    
    eval curl $curl_opts "$STACK_MANAGER_API$endpoint"
}

# Function to authenticate and get token
authenticate() {
    print_status "Authenticating with Stack Manager..."
    
    local auth_response=$(curl -s -X POST "$STACK_MANAGER_API/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{
            "email": "daniel@ttt.dev",
            "password": "SecureAdminPassword123"
        }')
    
    if [ $? -ne 0 ]; then
        print_error "Failed to authenticate"
        return 1
    fi
    
    AUTH_TOKEN=$(echo "$auth_response" | jq -r '.access_token // empty')
    
    if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" == "null" ]; then
        print_error "Failed to get auth token"
        echo "Response: $auth_response"
        return 1
    fi
    
    print_success "Authenticated successfully"
}

# Function to check if Stack Manager is running
check_stack_manager() {
    print_status "Checking Stack Manager availability..."
    
    if ! curl -s --connect-timeout 5 "$STACK_MANAGER_API/api/health" > /dev/null; then
        print_error "Stack Manager not available at $STACK_MANAGER_API"
        print_status "Please ensure Stack Manager is running with: ./install.sh --clean"
        return 1
    fi
    
    print_success "Stack Manager is available"
}

# Function to test monitoring service status
test_monitoring_status() {
    print_header "Testing Monitoring Service Status"
    
    local response=$(api_call GET "/api/credentials/monitoring/status")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get monitoring status"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local is_running=$(echo "$response" | jq -r '.service.isRunning // false')
    print_status "Monitoring service running: $is_running"
    
    print_success "Monitoring status check completed"
}

# Function to test manual monitoring check
test_manual_check() {
    print_header "Testing Manual Monitoring Check"
    
    print_status "Triggering manual credential check..."
    
    local response=$(api_call POST "/api/credentials/monitoring/check")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to trigger manual check"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local new_types=$(echo "$response" | jq -r '.result.newTypes // 0')
    local missing_types=$(echo "$response" | jq -r '.result.missingTypes // 0')
    
    print_status "Found $new_types new types, $missing_types missing types"
    print_success "Manual monitoring check completed"
}

# Function to test monitoring results
test_monitoring_results() {
    print_header "Testing Monitoring Results"
    
    local response=$(api_call GET "/api/credentials/monitoring/results?limit=5")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get monitoring results"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local count=$(echo "$response" | jq -r '.count // 0')
    print_status "Retrieved $count monitoring results"
    
    print_success "Monitoring results check completed"
}

# Function to test credential hints
test_credential_hints() {
    print_header "Testing Credential Hints"
    
    local response=$(api_call GET "/api/credentials/monitoring/hints")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get credential hints"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local count=$(echo "$response" | jq -r '.count // 0')
    print_status "Retrieved $count credential hints"
    
    if [ "$count" -gt 0 ]; then
        print_status "Sample hint types:"
        echo "$response" | jq -r '.hints[].type' | sort | uniq -c
    fi
    
    print_success "Credential hints check completed"
}

# Function to test system alerts
test_system_alerts() {
    print_header "Testing System Alerts"
    
    local response=$(api_call GET "/api/credentials/monitoring/alerts")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get system alerts"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local count=$(echo "$response" | jq -r '.count // 0')
    print_status "Retrieved $count system alerts"
    
    if [ "$count" -gt 0 ]; then
        print_status "Alert severities:"
        echo "$response" | jq -r '.alerts[].severity' | sort | uniq -c
    fi
    
    print_success "System alerts check completed"
}

# Function to test monitoring summary
test_monitoring_summary() {
    print_header "Testing Monitoring Summary"
    
    local response=$(api_call GET "/api/credentials/monitoring/summary")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get monitoring summary"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local last_check=$(echo "$response" | jq -r '.summary.last_check // "never"')
    local total_types=$(echo "$response" | jq -r '.summary.total_types // 0')
    local active_deprecations=$(echo "$response" | jq -r '.summary.active_deprecations // 0')
    
    print_status "Last check: $last_check"
    print_status "Total credential types: $total_types"
    print_status "Active deprecations: $active_deprecations"
    
    print_success "Monitoring summary check completed"
}

# Function to test new types detection
test_new_types() {
    print_header "Testing New Types Detection"
    
    local response=$(api_call GET "/api/credentials/monitoring/types/new")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get new types"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local count=$(echo "$response" | jq -r '.count // 0')
    print_status "Found $count new credential types"
    
    if [ "$count" -gt 0 ]; then
        print_status "New types:"
        echo "$response" | jq -r '.newTypes[].name'
    fi
    
    print_success "New types detection completed"
}

# Function to test missing types detection
test_missing_types() {
    print_header "Testing Missing Types Detection"
    
    local response=$(api_call GET "/api/credentials/monitoring/types/missing")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get missing types"
        return 1
    fi
    
    echo "$response" | jq '.'
    
    local count=$(echo "$response" | jq -r '.count // 0')
    print_status "Found $count missing credential types"
    
    if [ "$count" -gt 0 ]; then
        print_status "Missing types:"
        echo "$response" | jq -r '.missingTypes[]'
    fi
    
    print_success "Missing types detection completed"
}

# Function to start monitoring service
start_monitoring_service() {
    print_header "Starting Monitoring Service"
    
    local response=$(api_call POST "/api/credentials/monitoring/start")
    
    if [ $? -ne 0 ]; then
        print_warning "Failed to start monitoring service (might already be running)"
        return 0
    fi
    
    echo "$response" | jq '.'
    print_success "Monitoring service started"
}

# Function to stop monitoring service
stop_monitoring_service() {
    print_header "Stopping Monitoring Service"
    
    local response=$(api_call POST "/api/credentials/monitoring/stop")
    
    if [ $? -ne 0 ]; then
        print_warning "Failed to stop monitoring service"
        return 0
    fi
    
    echo "$response" | jq '.'
    print_success "Monitoring service stopped"
}

# Function to test database functions
test_database_functions() {
    print_header "Testing Database Functions"
    
    print_status "Testing monitoring summary function..."
    
    # Test the database function directly through API
    local response=$(api_call GET "/api/credentials/monitoring/summary")
    
    if [ $? -ne 0 ]; then
        print_error "Database function test failed"
        return 1
    fi
    
    local summary=$(echo "$response" | jq '.summary')
    if [ "$summary" == "null" ] || [ "$summary" == "{}" ]; then
        print_warning "Database function returned empty result"
    else
        print_success "Database functions working correctly"
    fi
}

# Function to run all tests
run_all_tests() {
    print_header "Running All Credential Monitoring Tests"
    
    # Pre-flight checks
    check_stack_manager || return 1
    authenticate || return 1
    
    # Core functionality tests
    test_monitoring_status || return 1
    test_database_functions || return 1
    
    # Start monitoring service
    start_monitoring_service || return 1
    
    # Monitoring tests
    test_manual_check || return 1
    test_monitoring_results || return 1
    test_credential_hints || return 1
    test_system_alerts || return 1
    test_monitoring_summary || return 1
    test_new_types || return 1
    test_missing_types || return 1
    
    # Clean up
    # stop_monitoring_service || return 1
    
    print_header "All Tests Completed Successfully"
    print_success "Credential monitoring system is working correctly!"
}

# Main execution
main() {
    print_header "Credential Monitoring System Test"
    print_status "Starting comprehensive test of the automated credential monitoring system"
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed"
        return 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        return 1
    fi
    
    # Run tests based on arguments
    case "${1:-all}" in
        "status")
            check_stack_manager && authenticate && test_monitoring_status
            ;;
        "check")
            check_stack_manager && authenticate && test_manual_check
            ;;
        "hints")
            check_stack_manager && authenticate && test_credential_hints
            ;;
        "summary")
            check_stack_manager && authenticate && test_monitoring_summary
            ;;
        "start")
            check_stack_manager && authenticate && start_monitoring_service
            ;;
        "stop")
            check_stack_manager && authenticate && stop_monitoring_service
            ;;
        "all"|*)
            run_all_tests
            ;;
    esac
}

# Script usage
if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    echo "Usage: $0 [test_type]"
    echo ""
    echo "Test types:"
    echo "  all      - Run all tests (default)"
    echo "  status   - Test monitoring service status"
    echo "  check    - Trigger manual monitoring check"
    echo "  hints    - Test credential hints"
    echo "  summary  - Test monitoring summary"
    echo "  start    - Start monitoring service"
    echo "  stop     - Stop monitoring service"
    echo ""
    echo "Prerequisites:"
    echo "  - Stack Manager running on port 3002"
    echo "  - Valid admin credentials (daniel@ttt.dev)"
    echo "  - jq and curl installed"
    exit 0
fi

# Execute main function
main "$@"