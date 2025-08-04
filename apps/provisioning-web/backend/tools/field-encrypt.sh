#!/bin/bash

# Field-Level Encryption Tool for .env files
# Encrypts only sensitive field values while keeping .env format intact
# Uses SOPS + Age for encryption of individual field values

set -euo pipefail

SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$PWD/.sops/age-key.txt}"
SOPS_AGE_RECIPIENTS="${SOPS_AGE_RECIPIENTS:-age13tmer078pe3zg7q5fenas2vq0ckaxdzl9k0hsf9nckrjharxxp8q0dg23l}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load logging functions
source "$(dirname "$0")/env-logger.sh" 2>/dev/null || {
    log_audit() { echo "AUDIT: $*"; }
    log_operation() { echo "OP: $*"; }
    log_encryption_event() { echo "CRYPT: $*"; }
    log_security_event() { echo "SEC: $*"; }
    log_error() { echo "ERROR: $*"; }
}

# Sensitive field patterns (case-insensitive)
SENSITIVE_PATTERNS=(
    "PASSWORD"
    "SECRET" 
    "KEY"
    "JWT"
    "TOKEN"
    "ANON_KEY"
    "SERVICE_ROLE_KEY"
    "ENCRYPTION_KEY"
    "VAULT_ENC_KEY"
    "N8N_ENCRYPTION_KEY"
    "WEBHOOK_SECRET"
    "API_KEY"
)

show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo -e "${BLUE}Field-Level Encryption Tool for .env Files${NC}"
    echo ""
    echo "Commands:"
    echo "  encrypt <file>         - Encrypt sensitive field values in file"
    echo "  decrypt <file>         - Decrypt field values in file"
    echo "  check <file>           - Check which fields would be encrypted"
    echo "  list-patterns          - Show sensitive field patterns"
    echo "  add-pattern <pattern>  - Add custom sensitive pattern"
    echo ""
    echo "Options:"
    echo "  --backup              - Create backup before encryption"
    echo "  --in-place            - Modify file in place (default: output to stdout)"
    echo "  --dry-run             - Show what would be done without making changes"
    echo ""
    echo "Examples:"
    echo "  $0 check .env                    # Check which fields are sensitive"
    echo "  $0 encrypt .env --backup         # Encrypt with backup"
    echo "  $0 decrypt .env.encrypted        # Decrypt values"
    echo ""
}

check_dependencies() {
    if ! command -v sops &> /dev/null; then
        echo -e "${RED}Error: SOPS not found${NC}"
        exit 1
    fi
    
    if ! command -v age &> /dev/null; then
        echo -e "${RED}Error: Age not found${NC}"
        exit 1
    fi
    
    if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
        echo -e "${RED}Error: Age key file not found at $SOPS_AGE_KEY_FILE${NC}"
        exit 1
    fi
}

is_sensitive_field() {
    local field_name="$1"
    local field_upper=$(echo "$field_name" | tr '[:lower:]' '[:upper:]')
    
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if [[ "$field_upper" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

encrypt_value() {
    local value="$1"
    
    # Get Age recipient from .sops/age-public-key.txt or use default
    local age_recipient="$SOPS_AGE_RECIPIENTS"
    if [ -f ".sops/age-public-key.txt" ]; then
        age_recipient=$(cat .sops/age-public-key.txt)
    fi
    
    # Encrypt using Age directly
    local encrypted
    if encrypted=$(echo -n "$value" | age -e -r "$age_recipient" 2>/dev/null | base64 -w 0); then
        echo "ENC[$encrypted]"
    else
        echo -e "${RED}Error: Failed to encrypt value${NC}" >&2
        return 1
    fi
}

decrypt_value() {
    local encrypted_value="$1"
    
    # Check if value is encrypted (starts with ENC[)
    if [[ "$encrypted_value" =~ ^ENC\[(.*)\]$ ]]; then
        local encoded="${BASH_REMATCH[1]}"
        
        # Decrypt using Age directly
        local decrypted
        if decrypted=$(echo -n "$encoded" | base64 -d | age -d -i "$SOPS_AGE_KEY_FILE" 2>/dev/null); then
            echo -n "$decrypted"
        else
            echo -e "${RED}Error: Failed to decrypt value${NC}" >&2
            return 1
        fi
    else
        # Value is not encrypted, return as-is
        echo -n "$encrypted_value"
    fi
}

process_env_file() {
    local action="$1"
    local file="$2"
    local output=""
    local changes_made=0
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File $file not found${NC}" >&2
        return 1
    fi
    
    log_operation "INFO" "Processing $file with action: $action" "Field-level encryption"
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            output+="$line"$'\n'
            continue
        fi
        
        # Parse KEY=VALUE lines
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove leading/trailing whitespace from key
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if is_sensitive_field "$key"; then
                case "$action" in
                    "encrypt")
                        # Only encrypt if not already encrypted
                        if [[ ! "$value" =~ ^ENC\[ ]]; then
                            local encrypted_value
                            if encrypted_value=$(encrypt_value "$value"); then
                                output+="$key=$encrypted_value"$'\n'
                                changes_made=1
                                log_encryption_event "FIELD_ENCRYPTED" "Field $key encrypted" "SUCCESS"
                            else
                                echo -e "${RED}Failed to encrypt field: $key${NC}" >&2
                                output+="$line"$'\n'
                                log_error "FIELD_ENCRYPT_FAILED" "Failed to encrypt field $key" "Encryption error"
                            fi
                        else
                            output+="$line"$'\n'
                        fi
                        ;;
                    "decrypt")
                        local decrypted_value
                        if decrypted_value=$(decrypt_value "$value"); then
                            output+="$key=$decrypted_value"$'\n'
                            if [[ "$value" =~ ^ENC\[ ]]; then
                                changes_made=1
                                log_encryption_event "FIELD_DECRYPTED" "Field $key decrypted" "SUCCESS"
                            fi
                        else
                            echo -e "${RED}Failed to decrypt field: $key${NC}" >&2
                            output+="$line"$'\n'
                            log_error "FIELD_DECRYPT_FAILED" "Failed to decrypt field $key" "Decryption error"
                        fi
                        ;;
                    "check")
                        local status="plaintext"
                        if [[ "$value" =~ ^ENC\[ ]]; then
                            status="encrypted"
                        fi
                        echo -e "  ${CYAN}$key${NC}: $status"
                        ;;
                esac
            else
                output+="$line"$'\n'
            fi
        else
            output+="$line"$'\n'
        fi
    done < "$file"
    
    if [ "$action" != "check" ]; then
        echo -n "$output"
    fi
    
    if [ $changes_made -eq 1 ]; then
        log_security_event "ENV_MODIFIED" "Environment file $file modified with $action" "MEDIUM"
    fi
    
    return 0
}

check_file() {
    local file="$1"
    
    echo -e "${YELLOW}Sensitive fields in $file:${NC}"
    process_env_file "check" "$file"
    echo ""
    
    # Count sensitive fields
    local total_sensitive=0
    local encrypted_count=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if is_sensitive_field "$key"; then
                ((total_sensitive++))
                if [[ "$value" =~ ^ENC\[ ]]; then
                    ((encrypted_count++))
                fi
            fi
        fi
    done < "$file"
    
    echo -e "${GREEN}Summary: $encrypted_count/$total_sensitive sensitive fields encrypted${NC}"
}

encrypt_file() {
    local file="$1"
    local backup="$2"
    local in_place="$3"
    local dry_run="$4"
    
    if [ "$dry_run" = "true" ]; then
        echo -e "${YELLOW}DRY RUN - Changes that would be made:${NC}"
        check_file "$file"
        return 0
    fi
    
    if [ "$backup" = "true" ]; then
        local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_file"
        echo -e "${GREEN}Backup created: $backup_file${NC}"
        log_operation "INFO" "Backup created" "File: $backup_file"
    fi
    
    local output
    if output=$(process_env_file "encrypt" "$file"); then
        if [ "$in_place" = "true" ]; then
            echo -n "$output" > "$file"
            echo -e "${GREEN}✓ File encrypted in place: $file${NC}"
        else
            echo -n "$output"
        fi
        log_security_event "FILE_ENCRYPTED" "Environment file $file encrypted" "HIGH"
    else
        log_error "FILE_ENCRYPT_FAILED" "Failed to encrypt file $file" "Process error"
        return 1
    fi
}

decrypt_file() {
    local file="$1"
    local in_place="$2"
    
    local output
    if output=$(process_env_file "decrypt" "$file"); then
        if [ "$in_place" = "true" ]; then
            echo -n "$output" > "$file"
            echo -e "${GREEN}✓ File decrypted in place: $file${NC}"
        else
            echo -n "$output"
        fi
        log_security_event "FILE_DECRYPTED" "Environment file $file decrypted" "HIGH"
    else
        log_error "FILE_DECRYPT_FAILED" "Failed to decrypt file $file" "Process error"
        return 1
    fi
}

list_patterns() {
    echo -e "${CYAN}Sensitive field patterns:${NC}"
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        echo "  $pattern"
    done
}

# Parse command line arguments
COMMAND=""
FILE=""
BACKUP=false
IN_PLACE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        encrypt|decrypt|check|list-patterns)
            COMMAND="$1"
            shift
            ;;
        --backup)
            BACKUP=true
            shift
            ;;
        --in-place)
            IN_PLACE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$FILE" ] && [ -n "$1" ] && [ "${1:0:1}" != "-" ]; then
                FILE="$1"
            fi
            shift
            ;;
    esac
done

# Check dependencies
check_dependencies

# Execute command
case "${COMMAND:-}" in
    "encrypt")
        if [ -z "$FILE" ]; then
            echo -e "${RED}Error: Please specify file to encrypt${NC}"
            exit 1
        fi
        encrypt_file "$FILE" "$BACKUP" "$IN_PLACE" "$DRY_RUN"
        ;;
    "decrypt")
        if [ -z "$FILE" ]; then
            echo -e "${RED}Error: Please specify file to decrypt${NC}"
            exit 1
        fi
        decrypt_file "$FILE" "$IN_PLACE"
        ;;
    "check")
        if [ -z "$FILE" ]; then
            echo -e "${RED}Error: Please specify file to check${NC}"
            exit 1
        fi
        check_file "$FILE"
        ;;
    "list-patterns")
        list_patterns
        ;;
    *)
        show_help
        exit 1
        ;;
esac