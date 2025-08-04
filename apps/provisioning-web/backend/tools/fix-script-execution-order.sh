#!/bin/bash

# Script Execution Order Fix
# This script resolves the dependency issue where script 04 references auth.users before auth schema is created

set -euo pipefail

# Configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Database connection helper
psql_exec() {
    local query="$1"
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -c "$query" 2>/dev/null
}

# Step 1: Clean up the problematic state
cleanup_problematic_state() {
    log "🧹 Cleaning up problematic database state..."
    
    # Mark script 04 as failed so it can be re-executed properly
    psql_exec "
        UPDATE init_script_tracking 
        SET status = 'FAILED', 
            completed_at = NOW(),
            error_message = 'Script execution order fix - foreign key dependency issue'
        WHERE script_name = '04-stack-manager-schema.sql' AND status = 'STARTED';
    "
    
    # Drop the problematic table that has invalid foreign key reference
    psql_exec "DROP TABLE IF EXISTS stack_manager.user_profiles CASCADE;" || true
    
    success "Problematic state cleaned up"
}

# Step 2: Execute auth schema creation first
create_auth_schema() {
    log "🔐 Creating auth schema and tables..."
    
    local script_dir="/home/devops/projects/active/agent-hosting/.dev/worktrees/credential-sync-work/platform/database/migrations/postgres"
    
    # Execute auth-related scripts in correct order
    local auth_scripts=(
        "05-0-gotrue-roles.sql"
        "05-1-create-auth-schema.sql"  
        "05-2-stack-manager-user.sql"
    )
    
    for script in "${auth_scripts[@]}"; do
        local script_file="$script_dir/$script"
        
        if [[ -f "$script_file" ]]; then
            log "Executing: $script"
            
            PGPASSWORD="$POSTGRES_PASSWORD" psql \
                -h "$POSTGRES_HOST" \
                -p "$POSTGRES_PORT" \
                -U "$POSTGRES_USER" \
                -d "$POSTGRES_DB" \
                -f "$script_file" \
                -v ON_ERROR_STOP=1 \
                --single-transaction
                
            success "Completed: $script"
        else
            error "Script not found: $script_file"
            return 1
        fi
    done
    
    success "Auth schema created successfully"
}

# Step 3: Re-execute script 04 now that auth schema exists
complete_stack_manager_schema() {
    log "🏗️ Completing stack manager schema..."
    
    local script_file="/home/devops/projects/active/agent-hosting/.dev/worktrees/credential-sync-work/platform/database/migrations/postgres/04-stack-manager-schema.sql"
    
    if [[ -f "$script_file" ]]; then
        log "Re-executing: 04-stack-manager-schema.sql"
        
        PGPASSWORD="$POSTGRES_PASSWORD" psql \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -d "$POSTGRES_DB" \
            -f "$script_file" \
            -v ON_ERROR_STOP=1 \
            --single-transaction
            
        success "Stack manager schema completed successfully"
    else
        error "Script 04 not found"
        return 1
    fi
}

# Step 4: Verify the fix worked
verify_fix() {
    log "✅ Verifying the fix..."
    
    # Check auth schema exists
    local auth_schema_exists=$(psql_exec "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'auth';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    
    if [[ "$auth_schema_exists" == "1" ]]; then
        success "Auth schema exists"
    else
        error "Auth schema missing"
        return 1
    fi
    
    # Check auth.users table exists
    local auth_users_exists=$(psql_exec "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    
    if [[ "$auth_users_exists" == "1" ]]; then
        success "auth.users table exists"
    else
        error "auth.users table missing"
        return 1
    fi
    
    # Check stack_manager.user_profiles table exists (should now work with foreign key)
    local user_profiles_exists=$(psql_exec "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'stack_manager' AND table_name = 'user_profiles';" | grep -v "^-" | grep -v "count" | grep -v "row" | xargs)
    
    if [[ "$user_profiles_exists" == "1" ]]; then
        success "stack_manager.user_profiles table exists with valid foreign key"
    else
        error "stack_manager.user_profiles table missing"
        return 1
    fi
    
    # Check script execution status
    local script04_status=$(psql_exec "SELECT status FROM init_script_tracking WHERE script_name = '04-stack-manager-schema.sql' ORDER BY started_at DESC LIMIT 1;" | grep -v "^-" | grep -v "status" | grep -v "row" | xargs)
    
    if [[ "$script04_status" == "COMPLETED" ]]; then
        success "Script 04 marked as completed"
    else
        warning "Script 04 status: $script04_status"
    fi
    
    success "All verification checks passed!"
}

# Main execution
main() {
    log "🚀 Starting Script Execution Order Fix..."
    log "============================================================"
    
    # Step 1: Clean up problematic state
    cleanup_problematic_state
    
    # Step 2: Create auth schema first
    create_auth_schema
    
    # Step 3: Complete stack manager schema
    complete_stack_manager_schema
    
    # Step 4: Verify the fix
    verify_fix
    
    success "Script execution order fix completed successfully!"
    log "✅ Dependencies resolved: auth schema → stack_manager references"
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi