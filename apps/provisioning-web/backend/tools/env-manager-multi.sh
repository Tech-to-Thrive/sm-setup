#!/bin/bash

# Multi-File Encrypted .env Management Tool for agent-hosting
# Supports Docker Compose (MVP), Docker Swarm, and Kubernetes
# Uses SOPS + Age for encryption
# Handles multiple .env files: .env, .env.auth, etc.

ENV_DIR="./startup/env-backups"
ENV_FILES=(".env" ".env.auth")  # Add more files as needed
METADATA_FILE="$ENV_DIR/metadata.json"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$PWD/.sops/age-key.txt}"
SOPS_AGE_RECIPIENTS="${SOPS_AGE_RECIPIENTS:-age13tmer078pe3zg7q5fenas2vq0ckaxdzl9k0hsf9nckrjharxxp8q0dg23l}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure PATH includes our tools
export PATH="$HOME/bin:$PATH"

# Load logging functions
source "$(dirname "$0")/env-logger.sh" 2>/dev/null || {
    echo "Warning: Logging system not available"
    # Define dummy logging functions if logger not available
    log_audit() { echo "AUDIT: $*"; }
    log_operation() { echo "OP: $*"; }
    log_env_change() { echo "ENV: $*"; }
    log_encryption_event() { echo "CRYPT: $*"; }
    log_security_event() { echo "SEC: $*"; }
    log_error() { echo "ERROR: $*"; }
}

# Ensure backup directory exists
mkdir -p "$ENV_DIR"

# Initialize metadata if not exists
if [ ! -f "$METADATA_FILE" ]; then
    echo '{"versions": [], "current": null}' > "$METADATA_FILE"
fi

check_dependencies() {
    if ! command -v sops &> /dev/null; then
        echo -e "${RED}Error: SOPS not found. Please install SOPS first.${NC}"
        echo "Run: wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 -O ~/bin/sops && chmod +x ~/bin/sops"
        exit 1
    fi
    
    if ! command -v age &> /dev/null; then
        echo -e "${RED}Error: Age not found. Please install Age first.${NC}"
        echo "Run: wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar -xzf age-v1.1.1-linux-amd64.tar.gz && mv age/* ~/bin/"
        exit 1
    fi
    
    if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
        echo -e "${YELLOW}Warning: Age key file not found at $SOPS_AGE_KEY_FILE${NC}"
        echo "To generate keys: mkdir -p .sops && age-keygen -o .sops/age-key.txt"
    fi
}

show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo -e "${BLUE}Multi-File Encrypted .env Management Tool${NC}"
    echo ""
    echo "Commands:"
    echo "  backup [description]    - Create encrypted versioned backup of all .env files"
    echo "  list                   - List all available versions"
    echo "  rollback <version>     - Rollback to specific version (decrypts automatically)"
    echo "  current                - Show current version info"
    echo "  diff <version>         - Compare current .env files with version"
    echo "  export <version>       - Export version for different platforms"
    echo "  decrypt <version> [file] - Decrypt specific version to stdout"
    echo "  setup                  - Initialize encryption keys"
    echo "  files                  - Show which .env files are managed"
    echo ""
    echo -e "${YELLOW}Field-Level Encryption Commands:${NC}"
    echo "  encrypt-fields [file]  - Encrypt sensitive field values in place"
    echo "  decrypt-fields [file]  - Decrypt field values in place"
    echo "  check-fields [file]    - Check which fields are sensitive/encrypted"
    echo ""
    echo "Options:"
    echo "  --file <filename>      - Operate on specific .env file only"
    echo ""
    echo "Environment Variables:"
    echo "  SOPS_AGE_KEY_FILE     - Path to Age private key (default: .sops/age-key.txt)"
    echo "  SOPS_AGE_RECIPIENTS   - Age public key for encryption"
    echo ""
    echo "Examples:"
    echo "  $0 backup \"Before SSL update\"      # Backup all .env files"
    echo "  $0 backup --file .env.auth \"Auth update\"  # Backup only .env.auth"
    echo "  $0 decrypt v20250620_102745 .env    # Decrypt specific file"
    echo "  $0 encrypt-fields .env             # Encrypt sensitive fields in .env"
    echo ""
}

get_env_files() {
    local files=()
    for file in "${ENV_FILES[@]}"; do
        if [ -f "$file" ]; then
            files+=("$file")
        fi
    done
    echo "${files[@]}"
}

setup_encryption() {
    echo -e "${BLUE}Setting up encryption...${NC}"
    log_operation "INFO" "Starting encryption setup" "SOPS+Age initialization"
    
    # Create SOPS directory
    mkdir -p .sops
    
    # Generate Age key if not exists
    if [ ! -f ".sops/age-key.txt" ]; then
        echo "Generating Age key pair..."
        log_security_event "KEY_GENERATION" "Generating new Age key pair" "MEDIUM"
        age-keygen -o .sops/age-key.txt
        log_encryption_event "KEY_GENERATED" "Age key pair created at .sops/age-key.txt" "SUCCESS"
        echo -e "${GREEN}✓ Age key pair generated${NC}"
    else
        echo -e "${YELLOW}Age key already exists${NC}"
        log_security_event "KEY_ACCESS" "Existing Age key found" "LOW"
    fi
    
    # Extract public key
    local public_key=$(grep "^age1" .sops/age-key.txt | head -1)
    echo "$public_key" > .sops/age-public-key.txt
    
    # Create .sops.yaml if not exists
    if [ ! -f ".sops.yaml" ]; then
        cat > .sops.yaml << EOF
creation_rules:
  - path_regex: \.env(\..*)?$
    age: $public_key
  - path_regex: env-backups/.*\.env.*$
    age: $public_key
EOF
        echo -e "${GREEN}✓ SOPS configuration created${NC}"
    else
        echo -e "${YELLOW}SOPS configuration already exists${NC}"
    fi
    
    echo -e "${GREEN}✓ Encryption setup complete${NC}"
    echo "Public key: $public_key"
    echo "Keep .sops/age-key.txt secure - this is your decryption key!"
    
    echo ""
    echo -e "${CYAN}Managed .env files:${NC}"
    show_files
}

show_files() {
    local found_files=($(get_env_files))
    
    if [ ${#found_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No .env files found${NC}"
        echo "Looking for: ${ENV_FILES[*]}"
    else
        for file in "${found_files[@]}"; do
            local size=$(du -h "$file" | cut -f1)
            echo -e "  ${GREEN}✓${NC} $file ($size)"
        done
    fi
}

backup_env() {
    local description="${1:-Manual backup}"
    local specific_file="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local version="v${timestamp}"
    local backup_base="$ENV_DIR/${version}"
    
    local files_to_backup=()
    if [ -n "$specific_file" ]; then
        if [ -f "$specific_file" ]; then
            files_to_backup=("$specific_file")
        else
            echo -e "${RED}Error: File $specific_file not found${NC}"
            exit 1
        fi
    else
        files_to_backup=($(get_env_files))
    fi
    
    if [ ${#files_to_backup[@]} -eq 0 ]; then
        echo -e "${RED}Error: No .env files found to backup${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Creating encrypted backup of ${#files_to_backup[@]} file(s)...${NC}"
    
    local backup_files=()
    local current_hashes=()
    
    # Backup each file
    local start_time=$(date +%s)
    for env_file in "${files_to_backup[@]}"; do
        local backup_file="${backup_base}$(echo "$env_file" | sed 's/^\.//').encrypted"
        echo -e "  ${CYAN}Encrypting${NC} $env_file → $(basename "$backup_file")"
        
        log_encryption_event "FILE_ENCRYPT_START" "Encrypting $env_file" "IN_PROGRESS"
        
        if ! SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -e --input-type dotenv --output-type dotenv "$env_file" > "$backup_file"; then
            echo -e "${RED}Error: Failed to encrypt $env_file${NC}"
            log_error "ENCRYPTION_FAILED" "Failed to encrypt $env_file" "SOPS encryption error"
            exit 1
        fi
        
        log_encryption_event "FILE_ENCRYPTED" "Successfully encrypted $env_file to $backup_file" "SUCCESS"
        backup_files+=("$backup_file")
        current_hashes+=("$(sha256sum "$env_file" | cut -d' ' -f1)")
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Update metadata
    local temp_file=$(mktemp)
    local files_json=$(printf '%s\n' "${files_to_backup[@]}" | jq -R . | jq -s .)
    local hashes_json=$(printf '%s\n' "${current_hashes[@]}" | jq -R . | jq -s .)
    
    jq --arg version "$version" \
       --arg timestamp "$timestamp" \
       --arg description "$description" \
       --argjson files "$files_json" \
       --argjson hashes "$hashes_json" \
       --arg encrypted "true" \
       '.versions += [{
           "version": $version,
           "timestamp": $timestamp,
           "description": $description,
           "files": $files,
           "hashes": $hashes,
           "encrypted": ($encrypted | test("true"))
       }] | .current = $version' "$METADATA_FILE" > "$temp_file"
    
    mv "$temp_file" "$METADATA_FILE"
    
    # Log completion
    log_env_change "BACKUP" "$version" "${files_to_backup[*]}" "$description" "SUCCESS"
    log_performance "BACKUP" "$duration" "${#files_to_backup[@]} files encrypted"
    
    echo -e "${GREEN}✓ Encrypted backup created: $version${NC}"
    echo -e "  Description: $description"
    echo -e "  Files: ${files_to_backup[*]}"
    echo -e "  Location: $backup_base*"
    echo -e "  Duration: ${duration}s"
}

list_versions() {
    echo -e "${YELLOW}Available .env backup versions:${NC}"
    echo ""
    
    if ! jq -e '.versions | length > 0' "$METADATA_FILE" >/dev/null 2>&1; then
        echo -e "${YELLOW}No backups found${NC}"
        return
    fi
    
    jq -r '.versions[] | "\(.version) - \(.timestamp) - \(.description) - \(if .encrypted then "🔒 encrypted" else "📄 plaintext" end) - Files: \(if .files then (.files | join(", ")) else ".env" end)"' "$METADATA_FILE" | \
    while read -r line; do
        echo "  $line"
    done
    
    echo ""
    local current=$(jq -r '.current // "none"' "$METADATA_FILE")
    echo -e "${GREEN}Current version: $current${NC}"
}

decrypt_version() {
    local target_version="$1"
    local specific_file="$2"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to decrypt${NC}"
        exit 1
    fi
    
    # Get files for this version
    local version_files
    if version_files=$(jq -r --arg version "$target_version" '.versions[] | select(.version == $version) | .files[]?' "$METADATA_FILE" 2>/dev/null); then
        local files_array=($version_files)
    else
        # Fallback for old format
        local files_array=(".env")
    fi
    
    if [ -n "$specific_file" ]; then
        # Check if requested file was backed up in this version
        local found=false
        for file in "${files_array[@]}"; do
            if [ "$file" = "$specific_file" ]; then
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            echo -e "${RED}Error: File $specific_file not found in version $target_version${NC}"
            echo "Available files: ${files_array[*]}"
            exit 1
        fi
        
        files_array=("$specific_file")
    fi
    
    # Decrypt requested files
    for env_file in "${files_array[@]}"; do
        local backup_file="$ENV_DIR/${target_version}$(echo "$env_file" | sed 's/^\.//').encrypted"
        
        if [ ! -f "$backup_file" ]; then
            echo -e "${RED}Error: Backup file not found: $backup_file${NC}"
            continue
        fi
        
        if [ ${#files_array[@]} -gt 1 ]; then
            echo -e "${CYAN}=== $env_file ===${NC}"
        fi
        
        # Check if file is encrypted
        if grep -q "sops:" "$backup_file" 2>/dev/null; then
            SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -d --input-type dotenv --output-type dotenv "$backup_file"
        else
            # File is not encrypted, just cat it
            cat "$backup_file"
        fi
        
        if [ ${#files_array[@]} -gt 1 ]; then
            echo ""
        fi
    done
}

rollback_env() {
    local target_version="$1"
    local specific_file="$2"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to rollback to${NC}"
        echo "Use: $0 list to see available versions"
        log_error "INVALID_ROLLBACK" "No version specified for rollback" "User error"
        exit 1
    fi
    
    # Check if version exists
    if ! jq -e --arg version "$target_version" '.versions[] | select(.version == $version)' "$METADATA_FILE" >/dev/null; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        log_error "VERSION_NOT_FOUND" "Rollback target version $target_version not found" "Invalid version"
        exit 1
    fi
    
    log_operation "INFO" "Starting rollback to $target_version" "Files: ${specific_file:-all}"
    log_security_event "ROLLBACK_INITIATED" "Rollback to version $target_version requested" "MEDIUM"
    
    # Backup current before rollback
    backup_env "Pre-rollback backup"
    
    echo -e "${BLUE}Rolling back to $target_version...${NC}"
    
    # Get files for this version
    local version_files
    if version_files=$(jq -r --arg version "$target_version" '.versions[] | select(.version == $version) | .files[]?' "$METADATA_FILE" 2>/dev/null); then
        local files_array=($version_files)
    else
        # Fallback for old format
        local files_array=(".env")
    fi
    
    if [ -n "$specific_file" ]; then
        files_array=("$specific_file")
    fi
    
    # Restore each file
    for env_file in "${files_array[@]}"; do
        local backup_file="$ENV_DIR/${target_version}$(echo "$env_file" | sed 's/^\.//').encrypted"
        
        if [ ! -f "$backup_file" ]; then
            echo -e "${YELLOW}Warning: Backup file not found: $backup_file${NC}"
            continue
        fi
        
        echo -e "  ${CYAN}Restoring${NC} $env_file"
        
        log_encryption_event "FILE_DECRYPT_START" "Decrypting $env_file from $target_version" "IN_PROGRESS"
        
        # Decrypt and restore
        if grep -q "sops:" "$backup_file" 2>/dev/null; then
            if ! SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -d --input-type dotenv --output-type dotenv "$backup_file" > "$env_file"; then
                echo -e "${RED}Error: Failed to decrypt and restore $env_file from $target_version${NC}"
                log_error "DECRYPT_FAILED" "Failed to decrypt $env_file from $target_version" "SOPS decryption error"
                exit 1
            fi
            log_encryption_event "FILE_DECRYPTED" "Successfully decrypted $env_file from $target_version" "SUCCESS"
        else
            cp "$backup_file" "$env_file"
            log_operation "INFO" "Copied plaintext file $env_file" "No decryption needed"
        fi
    done
    
    # Update current version in metadata
    local temp_file=$(mktemp)
    jq --arg version "$target_version" '.current = $version' "$METADATA_FILE" > "$temp_file"
    mv "$temp_file" "$METADATA_FILE"
    
    log_env_change "ROLLBACK" "$target_version" "${files_array[*]}" "Rollback completed" "SUCCESS"
    log_security_event "ROLLBACK_COMPLETED" "Successfully rolled back to $target_version" "MEDIUM"
    
    echo -e "${GREEN}✓ Rolled back to version: $target_version${NC}"
    echo -e "${YELLOW}⚠ Remember to restart your stack to apply changes${NC}"
}

show_current() {
    local current=$(jq -r '.current // "none"' "$METADATA_FILE")
    echo -e "${GREEN}Current version: $current${NC}"
    
    if [ "$current" != "none" ]; then
        jq -r --arg version "$current" '.versions[] | select(.version == $version) | "  Timestamp: \(.timestamp)\n  Description: \(.description)\n  Files: \(if .files then (.files | join(", ")) else ".env" end)\n  Encrypted: \(if .encrypted then "🔒 Yes" else "📄 No" end)"' "$METADATA_FILE"
    fi
}

diff_env() {
    local target_version="$1"
    local specific_file="$2"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to compare${NC}"
        exit 1
    fi
    
    # Get files for this version
    local version_files
    if version_files=$(jq -r --arg version "$target_version" '.versions[] | select(.version == $version) | .files[]?' "$METADATA_FILE" 2>/dev/null); then
        local files_array=($version_files)
    else
        local files_array=(".env")
    fi
    
    if [ -n "$specific_file" ]; then
        files_array=("$specific_file")
    fi
    
    echo -e "${YELLOW}Differences between current files and $target_version:${NC}"
    
    # Compare each file
    for env_file in "${files_array[@]}"; do
        if [ ! -f "$env_file" ]; then
            echo -e "${RED}Current file $env_file not found${NC}"
            continue
        fi
        
        local backup_file="$ENV_DIR/${target_version}$(echo "$env_file" | sed 's/^\.//').encrypted"
        
        if [ ! -f "$backup_file" ]; then
            echo -e "${RED}Backup file not found: $backup_file${NC}"
            continue
        fi
        
        echo -e "${CYAN}=== $env_file ===${NC}"
        
        # Create temp file for decrypted version
        local temp_file=$(mktemp)
        if grep -q "sops:" "$backup_file" 2>/dev/null; then
            SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -d --input-type dotenv --output-type dotenv "$backup_file" > "$temp_file"
        else
            cp "$backup_file" "$temp_file"
        fi
        
        diff -u "$temp_file" "$env_file" || true
        rm -f "$temp_file"
        echo ""
    done
}

export_env() {
    local target_version="$1"
    local platform="${2:-compose}"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to export${NC}"
        exit 1
    fi
    
    # Check if version exists
    if ! jq -e --arg version "$target_version" '.versions[] | select(.version == $version)' "$METADATA_FILE" >/dev/null; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        exit 1
    fi
    
    case "$platform" in
        "swarm")
            echo -e "${YELLOW}Exporting for Docker Swarm:${NC}"
            echo "# Create temporary decrypted files:"
            echo "$0 decrypt $target_version > /dev/null"  # This will output all files
            echo "# For each .env file, create Docker secrets:"
            echo "docker secret create app-env-main-$target_version <(echo \"\$($0 decrypt $target_version .env)\")"
            echo "docker secret create app-env-auth-$target_version <(echo \"\$($0 decrypt $target_version .env.auth)\")"
            echo "# Reference in docker-compose.yml with external: true"
            ;;
        "k8s"|"kubernetes")
            echo -e "${YELLOW}Exporting for Kubernetes:${NC}"
            echo "# Create temporary files and secrets:"
            echo "$0 decrypt $target_version .env > /tmp/$target_version.env"
            echo "$0 decrypt $target_version .env.auth > /tmp/$target_version.env.auth"
            echo "kubectl create secret generic app-env-main-$target_version --from-env-file=/tmp/$target_version.env"
            echo "kubectl create secret generic app-env-auth-$target_version --from-env-file=/tmp/$target_version.env.auth"
            echo "# Clean up:"
            echo "rm /tmp/$target_version.env*"
            ;;
        "compose"|*)
            echo -e "${YELLOW}Exporting for Docker Compose:${NC}"
            echo "# Decrypt files to current directory:"
            echo "$0 decrypt $target_version .env > .env"
            echo "$0 decrypt $target_version .env.auth > .env.auth"
            ;;
    esac
}

# Parse command line arguments
COMMAND=""
SPECIFIC_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        setup|backup|list|rollback|current|diff|decrypt|export|files|encrypt-fields|decrypt-fields|check-fields|help|--help|-h)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            fi
            shift
            ;;
    esac
done

# Check dependencies first
check_dependencies

# Main command handling
case "${COMMAND:-}" in
    "setup")
        setup_encryption
        ;;
    "backup")
        backup_env "$1" "$SPECIFIC_FILE"
        ;;
    "list")
        list_versions
        ;;
    "rollback")
        rollback_env "$1" "$SPECIFIC_FILE"
        ;;
    "current")
        show_current
        ;;
    "diff")
        diff_env "$1" "$SPECIFIC_FILE"
        ;;
    "decrypt")
        decrypt_version "$1" "$2"
        ;;
    "export")
        export_env "$1" "$2"
        ;;
    "files")
        echo -e "${CYAN}Managed .env files:${NC}"
        show_files
        ;;
    "encrypt-fields")
        target_file="${1:-.env}"
        echo -e "${BLUE}Encrypting sensitive fields in $target_file...${NC}"
        if ./tools/field-encrypt.sh encrypt "$target_file" --in-place --backup; then
            log_operation "INFO" "Field encryption completed" "File: $target_file"
        else
            log_error "FIELD_ENCRYPT_FAILED" "Field encryption failed for $target_file" "Process error"
            exit 1
        fi
        ;;
    "decrypt-fields")
        target_file="${1:-.env}"
        echo -e "${BLUE}Decrypting fields in $target_file...${NC}"
        if ./tools/field-encrypt.sh decrypt "$target_file" --in-place; then
            log_operation "INFO" "Field decryption completed" "File: $target_file"
        else
            log_error "FIELD_DECRYPT_FAILED" "Field decryption failed for $target_file" "Process error"
            exit 1
        fi
        ;;
    "check-fields")
        target_file="${1:-.env}"
        ./tools/field-encrypt.sh check "$target_file"
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        show_help
        exit 1
        ;;
esac