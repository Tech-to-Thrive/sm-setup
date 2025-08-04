#!/bin/bash

# Database Recovery Script
# Systematic approach to complete database initialization
# Author: Claude Code
# Date: 2025-06-27

set -euo pipefail

# Configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
SCRIPT_DIR="/home/devops/projects/active/agent-hosting/.dev/worktrees/credential-sync-work/platform/database/migrations/postgres"
LOG_FILE="/tmp/database-recovery-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Database connection helper
psql_exec() {
    local query="$1"
    local db="${2:-$POSTGRES_DB}"
    
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$db" \
        -c "$query" 2>/dev/null
}

# Execute SQL file with proper error handling
psql_exec_file() {
    local file="$1"
    local db="${2:-$POSTGRES_DB}"
    
    log "Executing SQL file: $(basename "$file")"
    
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$db" \
        -f "$file" \
        -v ON_ERROR_STOP=1 \
        --single-transaction 2>>"$LOG_FILE"
}

# Check database connectivity
check_database_connectivity() {
    log "Checking database connectivity..."
    
    if ! psql_exec "SELECT 1;" >/dev/null 2>&1; then
        error "Cannot connect to PostgreSQL database"
        return 1
    fi
    
    success "Database connectivity verified"
    return 0
}

# Get current script execution status
get_script_status() {
    local script_name="$1"
    
    psql_exec "
        SELECT status FROM init_script_tracking 
        WHERE script_name = '$script_name' 
        ORDER BY started_at DESC LIMIT 1;
    " | grep -v "^-" | grep -v "status" | grep -v "row" | xargs || echo "NOT_FOUND"
}

# Mark script as failed and clean up partial execution
cleanup_stuck_script() {
    local script_name="$1"
    
    log "Cleaning up stuck script: $script_name"
    
    # Update script status to failed
    psql_exec "
        UPDATE init_script_tracking 
        SET status = 'FAILED', 
            completed_at = NOW(),
            error_message = 'Script execution interrupted - cleaned up for retry'
        WHERE script_name = '$script_name' AND status = 'STARTED';
    "
    
    # Remove the problematic user_profiles table that has invalid foreign key
    psql_exec "DROP TABLE IF EXISTS stack_manager.user_profiles CASCADE;" || true
    
    success "Script $script_name marked as failed and cleaned up"
}

# Execute a single initialization script
execute_script() {
    local script_file="$1"
    local script_name=$(basename "$script_file")
    
    local current_status=$(get_script_status "$script_name")
    
    case "$current_status" in
        "COMPLETED")
            log "Script $script_name already completed, skipping"
            return 0
            ;;
        "STARTED")
            warning "Script $script_name is stuck, cleaning up first"
            cleanup_stuck_script "$script_name"
            ;;
        "FAILED"|"NOT_FOUND")
            log "Script $script_name needs to be executed"
            ;;
    esac
    
    log "Executing script: $script_name"
    
    if psql_exec_file "$script_file"; then
        success "Script $script_name completed successfully"
        return 0
    else
        error "Script $script_name failed to execute"
        return 1
    fi
}

# Get list of scripts that need to be executed
get_pending_scripts() {
    # List all scripts in order, excluding those already completed
    find "$SCRIPT_DIR" -name "*.sql" -type f | sort | while read -r script_file; do
        local script_name=$(basename "$script_file")
        local status=$(get_script_status "$script_name")
        
        if [[ "$status" != "COMPLETED" ]]; then
            echo "$script_file"
        fi
    done
}

# Create backup before making changes
create_backup() {
    log "Creating database backup before recovery..."
    
    local backup_file="/tmp/database-backup-$(date +%Y%m%d_%H%M%S).sql"
    
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --clean \
        --create \
        --if-exists \
        > "$backup_file" 2>>"$LOG_FILE"
    
    if [[ -f "$backup_file" ]]; then
        success "Database backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        error "Failed to create database backup"
        return 1
    fi
}

# Validate database state after recovery
validate_recovery() {
    log "Validating database recovery..."
    
    # Check if validation script exists
    local validator="/home/devops/projects/active/agent-hosting/.dev/worktrees/credential-sync-work/tools/database-validation-tests.js"
    
    if [[ -f "$validator" ]]; then
        log "Running comprehensive validation tests..."
        if node "$validator" 2>>"$LOG_FILE"; then
            success "All validation tests passed"
            return 0
        else
            warning "Some validation tests failed - check detailed output"
            return 1
        fi
    else
        log "Validation script not found, performing basic checks..."
        
        # Basic schema check
        local schema_count=$(psql_exec "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name IN ('public', 'stack_manager', 'auth');" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
        
        if [[ "$schema_count" == "3" ]]; then
            success "All expected schemas present"
            return 0
        else
            error "Expected 3 schemas, found $schema_count"
            return 1
        fi
    fi
}

# Restart dependent services after database recovery
restart_services() {
    log "Restarting dependent services..."
    
    local services=(
        "auth-gotrue"
        "app-stackmanager-api"
        "app-stackmanager-ui"
        "app-stackmanager-scheduler"
    )
    
    for service in "${services[@]}"; do
        log "Restarting service: $service"
        if docker restart "$service" >/dev/null 2>&1; then
            success "Service $service restarted successfully"
        else
            warning "Failed to restart service: $service"
        fi
    done
    
    # Wait for services to stabilize
    log "Waiting for services to stabilize..."
    sleep 10
}

# Main recovery process
main() {
    log "=== Database Recovery Process Started ==="
    log "Log file: $LOG_FILE"
    
    # Phase 1: Pre-flight checks
    log "\n🔍 Phase 1: Pre-flight checks"
    
    if ! check_database_connectivity; then
        error "Database connectivity check failed"
        exit 1
    fi
    
    # Create backup
    local backup_file
    if backup_file=$(create_backup); then
        log "Backup created successfully: $backup_file"
    else
        error "Backup creation failed"
        exit 1
    fi
    
    # Phase 2: Analyze current state
    log "\n📊 Phase 2: Analyzing current state"
    
    # Count completed scripts
    local completed_count=$(psql_exec "SELECT COUNT(*) FROM init_script_tracking WHERE status = 'COMPLETED';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    local stuck_count=$(psql_exec "SELECT COUNT(*) FROM init_script_tracking WHERE status = 'STARTED';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    local failed_count=$(psql_exec "SELECT COUNT(*) FROM init_script_tracking WHERE status = 'FAILED';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    
    log "Current state: $completed_count completed, $stuck_count stuck, $failed_count failed"
    
    # Get list of pending scripts
    local pending_scripts
    mapfile -t pending_scripts < <(get_pending_scripts)
    
    log "Found ${#pending_scripts[@]} scripts pending execution"
    
    if [[ ${#pending_scripts[@]} -eq 0 ]]; then
        success "All scripts already completed!"
        validate_recovery
        exit 0
    fi
    
    # Phase 3: Execute pending scripts
    log "\n🚀 Phase 3: Executing pending scripts"
    
    local success_count=0
    local failure_count=0
    
    for script_file in "${pending_scripts[@]}"; do
        local script_name=$(basename "$script_file")
        
        log "\n--- Processing script: $script_name ---"
        
        if execute_script "$script_file"; then
            ((success_count++))
        else
            ((failure_count++))
            error "Script execution failed: $script_name"
            
            # Stop on first failure for safety
            error "Stopping execution due to script failure"
            break
        fi
    done
    
    # Phase 4: Validation and service restart
    log "\n✅ Phase 4: Validation and service restart"
    
    log "Execution summary: $success_count successful, $failure_count failed"
    
    if [[ $failure_count -eq 0 ]]; then
        success "All pending scripts executed successfully!"
        
        # Validate the recovery
        if validate_recovery; then
            success "Database validation passed"
        else
            warning "Database validation had issues"
        fi
        
        # Restart services
        restart_services
        
        success "Database recovery completed successfully!"
        log "Backup file available at: $backup_file"
        log "Log file available at: $LOG_FILE"
        
    else
        error "Database recovery completed with errors"
        log "Backup file available for rollback: $backup_file"
        log "Log file available at: $LOG_FILE"
        exit 1
    fi
    
    log "=== Database Recovery Process Completed ==="
}

# Script execution check
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi