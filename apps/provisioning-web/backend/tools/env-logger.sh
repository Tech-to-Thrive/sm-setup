#!/bin/bash

# Environment Operations Logger
# Provides comprehensive logging for all environment management operations

LOG_DIR="${LOG_DIR:-./startup/logs}"
DATE_SUFFIX=$(date '+%Y%m%d')
AUDIT_LOG="$LOG_DIR/env-audit-$DATE_SUFFIX.log"
OPERATIONS_LOG="$LOG_DIR/env-operations-$DATE_SUFFIX.log"
ERROR_LOG="$LOG_DIR/env-errors-$DATE_SUFFIX.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Initialize log files if they don't exist
[ ! -f "$AUDIT_LOG" ] && echo "# Environment Operations Audit Log - Started $(date)" > "$AUDIT_LOG"
[ ! -f "$OPERATIONS_LOG" ] && echo "# Environment Operations Log - Started $(date)" > "$OPERATIONS_LOG"
[ ! -f "$ERROR_LOG" ] && echo "# Environment Errors Log - Started $(date)" > "$ERROR_LOG"

log_audit() {
    local command="$1"
    local status="$2"
    local details="$3"
    local user="${USER:-unknown}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    
    echo "[$timestamp] [$user@$hostname] [$command] [$status] $details" >> "$AUDIT_LOG"
}

log_operation() {
    local level="$1"  # INFO, WARN, ERROR
    local message="$2"
    local context="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${USER:-unknown}"
    
    echo "[$timestamp] [$level] [$user] $message ${context:+- $context}" >> "$OPERATIONS_LOG"
    
    # Also log errors to separate error log
    if [ "$level" = "ERROR" ]; then
        echo "[$timestamp] [$user] $message ${context:+- $context}" >> "$ERROR_LOG"
    fi
}

log_env_change() {
    local operation="$1"  # BACKUP, ROLLBACK, DECRYPT, etc.
    local version="$2"
    local files="$3"
    local description="$4"
    local status="$5"     # SUCCESS, FAILED, PARTIAL
    
    log_audit "$operation" "$status" "Version: $version, Files: $files, Description: $description"
    log_operation "INFO" "Environment $operation completed" "Version: $version, Status: $status"
}

log_encryption_event() {
    local event_type="$1"  # KEY_GENERATED, FILE_ENCRYPTED, FILE_DECRYPTED, etc.
    local details="$2"
    local status="$3"
    
    log_audit "ENCRYPTION_$event_type" "$status" "$details"
    log_operation "INFO" "Encryption event: $event_type" "$details"
}

log_security_event() {
    local event="$1"      # KEY_ACCESS, DECRYPT_ATTEMPT, etc.
    local details="$2"
    local severity="$3"   # LOW, MEDIUM, HIGH, CRITICAL
    
    log_audit "SECURITY_$event" "$severity" "$details"
    log_operation "WARN" "Security event: $event ($severity)" "$details"
}

log_error() {
    local error_type="$1"
    local error_message="$2"
    local context="$3"
    
    log_audit "ERROR_$error_type" "FAILED" "$error_message"
    log_operation "ERROR" "$error_type: $error_message" "$context"
}

# Performance tracking
log_performance() {
    local operation="$1"
    local duration="$2"
    local details="$3"
    
    log_operation "INFO" "Performance: $operation took ${duration}s" "$details"
}

# Compliance logging for sensitive operations
log_compliance() {
    local regulation="$1"  # GDPR, SOX, HIPAA, etc.
    local operation="$2"
    local justification="$3"
    
    log_audit "COMPLIANCE_$regulation" "LOGGED" "Operation: $operation, Justification: $justification"
}

# System state logging
log_system_state() {
    local component="$1"
    local state="$2"
    local metrics="$3"
    
    log_operation "INFO" "System state: $component is $state" "$metrics"
}

# Export functions for use in other scripts
export -f log_audit log_operation log_env_change log_encryption_event
export -f log_security_event log_error log_performance log_compliance log_system_state

# If script is called directly, provide logging utilities
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "test")
            echo "Testing logging system..."
            log_audit "TEST" "SUCCESS" "Logging system test"
            log_operation "INFO" "Test message" "Context: logging test"
            log_env_change "TEST_BACKUP" "v20250620_test" ".env" "Test backup" "SUCCESS"
            log_encryption_event "TEST_ENCRYPT" "Test file" "SUCCESS"
            log_security_event "TEST_ACCESS" "Test access event" "LOW"
            echo "Test logs written to: $LOG_DIR"
            ;;
        "rotate")
            # Log rotation
            for log_file in "$AUDIT_LOG" "$OPERATIONS_LOG" "$ERROR_LOG"; do
                if [ -f "$log_file" ] && [ $(wc -l < "$log_file") -gt 10000 ]; then
                    mv "$log_file" "${log_file}.$(date +%Y%m%d_%H%M%S)"
                    echo "# Log rotated $(date)" > "$log_file"
                    log_operation "INFO" "Log rotated" "File: $log_file"
                fi
            done
            ;;
        "summary")
            echo "=== Environment Operations Summary ==="
            echo "Date: $(date '+%Y-%m-%d')"
            echo ""
            echo "Today's logs:"
            echo "  Audit entries: $(wc -l < "$AUDIT_LOG" 2>/dev/null || echo 0)"
            echo "  Operation entries: $(wc -l < "$OPERATIONS_LOG" 2>/dev/null || echo 0)"
            echo "  Error entries: $(wc -l < "$ERROR_LOG" 2>/dev/null || echo 0)"
            echo ""
            echo "All log files:"
            ls -la "$LOG_DIR"/*.log 2>/dev/null || echo "No log files found"
            echo ""
            echo "Recent errors (today):"
            tail -5 "$ERROR_LOG" 2>/dev/null || echo "No errors logged today"
            ;;
        "clean")
            # Clean old logs (keep last 90 days)
            find "$LOG_DIR" -name "*.log.*" -mtime +90 -delete 2>/dev/null || true
            log_operation "INFO" "Log cleanup completed" "Removed logs older than 90 days"
            ;;
        *)
            echo "Usage: $0 {test|rotate|summary|clean}"
            echo ""
            echo "Available logging functions:"
            echo "  log_audit <command> <status> <details>"
            echo "  log_operation <level> <message> <context>"
            echo "  log_env_change <operation> <version> <files> <description> <status>"
            echo "  log_encryption_event <event_type> <details> <status>"
            echo "  log_security_event <event> <details> <severity>"
            echo "  log_error <error_type> <error_message> <context>"
            echo "  log_performance <operation> <duration> <details>"
            echo "  log_compliance <regulation> <operation> <justification>"
            echo "  log_system_state <component> <state> <metrics>"
            ;;
    esac
fi