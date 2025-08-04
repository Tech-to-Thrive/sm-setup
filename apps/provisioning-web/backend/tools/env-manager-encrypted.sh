#!/bin/bash

# Encrypted .env Management Tool for agent-hosting
# Supports Docker Compose (MVP), Docker Swarm, and Kubernetes
# Uses SOPS + Age for encryption

ENV_DIR="./startup/env-backups"
ENV_FILE=".env"
METADATA_FILE="$ENV_DIR/metadata.json"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$PWD/.sops/age-key.txt}"
SOPS_AGE_RECIPIENTS="${SOPS_AGE_RECIPIENTS:-age13tmer078pe3zg7q5fenas2vq0ckaxdzl9k0hsf9nckrjharxxp8q0dg23l}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure PATH includes our tools
export PATH="$HOME/bin:$PATH"

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
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo -e "${BLUE}Encrypted .env Management Tool${NC}"
    echo ""
    echo "Commands:"
    echo "  backup [description]    - Create encrypted versioned backup of current .env"
    echo "  list                   - List all available versions"
    echo "  rollback <version>     - Rollback to specific version (decrypts automatically)"
    echo "  current                - Show current version info"
    echo "  diff <version>         - Compare current .env with version"
    echo "  export <version>       - Export version for different platforms"
    echo "  decrypt <version>      - Decrypt specific version to stdout"
    echo "  setup                  - Initialize encryption keys"
    echo ""
    echo "Environment Variables:"
    echo "  SOPS_AGE_KEY_FILE     - Path to Age private key (default: .sops/age-key.txt)"
    echo "  SOPS_AGE_RECIPIENTS   - Age public key for encryption"
    echo ""
}

setup_encryption() {
    echo -e "${BLUE}Setting up encryption...${NC}"
    
    # Create SOPS directory
    mkdir -p .sops
    
    # Generate Age key if not exists
    if [ ! -f ".sops/age-key.txt" ]; then
        echo "Generating Age key pair..."
        age-keygen -o .sops/age-key.txt
        echo -e "${GREEN}✓ Age key pair generated${NC}"
    else
        echo -e "${YELLOW}Age key already exists${NC}"
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
  - path_regex: env-backups/.*\.env$
    age: $public_key
EOF
        echo -e "${GREEN}✓ SOPS configuration created${NC}"
    else
        echo -e "${YELLOW}SOPS configuration already exists${NC}"
    fi
    
    echo -e "${GREEN}✓ Encryption setup complete${NC}"
    echo "Public key: $public_key"
    echo "Keep .sops/age-key.txt secure - this is your decryption key!"
}

backup_env() {
    local description="${1:-Manual backup}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local version="v${timestamp}"
    local backup_file="$ENV_DIR/${version}.env"
    
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}Error: .env file not found${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Creating encrypted backup...${NC}"
    
    # Encrypt and create backup
    if ! SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -e --input-type dotenv --output-type dotenv "$ENV_FILE" > "$backup_file"; then
        echo -e "${RED}Error: Failed to encrypt .env file${NC}"
        exit 1
    fi
    
    # Update metadata
    local current_hash=$(sha256sum "$ENV_FILE" | cut -d' ' -f1)
    local temp_file=$(mktemp)
    
    jq --arg version "$version" \
       --arg timestamp "$timestamp" \
       --arg description "$description" \
       --arg hash "$current_hash" \
       --arg encrypted "true" \
       '.versions += [{
           "version": $version,
           "timestamp": $timestamp,
           "description": $description,
           "hash": $hash,
           "encrypted": ($encrypted | test("true"))
       }] | .current = $version' "$METADATA_FILE" > "$temp_file"
    
    mv "$temp_file" "$METADATA_FILE"
    
    echo -e "${GREEN}✓ Encrypted backup created: $version${NC}"
    echo -e "  Description: $description"
    echo -e "  File: $backup_file (encrypted)"
}

list_versions() {
    echo -e "${YELLOW}Available .env versions:${NC}"
    echo ""
    
    jq -r '.versions[] | "\(.version) - \(.timestamp) - \(.description) - \(if .encrypted then "🔒 encrypted" else "📄 plaintext" end)"' "$METADATA_FILE" | \
    while read -r line; do
        echo "  $line"
    done
    
    echo ""
    local current=$(jq -r '.current // "none"' "$METADATA_FILE")
    echo -e "${GREEN}Current version: $current${NC}"
}

decrypt_version() {
    local target_version="$1"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to decrypt${NC}"
        exit 1
    fi
    
    local backup_file="$ENV_DIR/${target_version}.env"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        exit 1
    fi
    
    # Check if file is encrypted
    if grep -q "sops:" "$backup_file" 2>/dev/null; then
        SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" sops -d --input-type dotenv --output-type dotenv "$backup_file"
    else
        # File is not encrypted, just cat it
        cat "$backup_file"
    fi
}

rollback_env() {
    local target_version="$1"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to rollback to${NC}"
        echo "Use: $0 list to see available versions"
        exit 1
    fi
    
    local backup_file="$ENV_DIR/${target_version}.env"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        exit 1
    fi
    
    # Backup current before rollback
    backup_env "Pre-rollback backup"
    
    echo -e "${BLUE}Rolling back to $target_version...${NC}"
    
    # Decrypt and restore
    if ! decrypt_version "$target_version" > "$ENV_FILE"; then
        echo -e "${RED}Error: Failed to decrypt and restore version $target_version${NC}"
        exit 1
    fi
    
    # Update current version in metadata
    local temp_file=$(mktemp)
    jq --arg version "$target_version" '.current = $version' "$METADATA_FILE" > "$temp_file"
    mv "$temp_file" "$METADATA_FILE"
    
    echo -e "${GREEN}✓ Rolled back to version: $target_version${NC}"
    echo -e "${YELLOW}⚠ Remember to restart your stack to apply changes${NC}"
}

show_current() {
    local current=$(jq -r '.current // "none"' "$METADATA_FILE")
    echo -e "${GREEN}Current version: $current${NC}"
    
    if [ "$current" != "none" ]; then
        jq -r --arg version "$current" '.versions[] | select(.version == $version) | "  Timestamp: \(.timestamp)\n  Description: \(.description)\n  Encrypted: \(if .encrypted then "🔒 Yes" else "📄 No" end)"' "$METADATA_FILE"
    fi
}

diff_env() {
    local target_version="$1"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to compare${NC}"
        exit 1
    fi
    
    local backup_file="$ENV_DIR/${target_version}.env"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Differences between current .env and $target_version:${NC}"
    
    # Create temp file for decrypted version
    local temp_file=$(mktemp)
    decrypt_version "$target_version" > "$temp_file"
    
    diff -u "$temp_file" "$ENV_FILE" || true
    rm -f "$temp_file"
}

export_env() {
    local target_version="$1"
    local platform="${2:-compose}"
    
    if [ -z "$target_version" ]; then
        echo -e "${RED}Error: Please specify version to export${NC}"
        exit 1
    fi
    
    local backup_file="$ENV_DIR/${target_version}.env"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Version $target_version not found${NC}"
        exit 1
    fi
    
    case "$platform" in
        "swarm")
            echo -e "${YELLOW}Exporting for Docker Swarm:${NC}"
            echo "# Create temporary decrypted file:"
            echo "$0 decrypt $target_version > /tmp/$target_version.env"
            echo "# Create Docker secret:"
            echo "docker secret create app-env-$target_version /tmp/$target_version.env"
            echo "# Clean up:"
            echo "rm /tmp/$target_version.env"
            echo "# Reference in docker-compose.yml with external: true"
            ;;
        "k8s"|"kubernetes")
            echo -e "${YELLOW}Exporting for Kubernetes:${NC}"
            echo "# Create temporary decrypted file:"
            echo "$0 decrypt $target_version > /tmp/$target_version.env"
            echo "# Create Kubernetes secret:"
            echo "kubectl create secret generic app-env-$target_version --from-env-file=/tmp/$target_version.env"
            echo "# Clean up:"
            echo "rm /tmp/$target_version.env"
            ;;
        "compose"|*)
            echo -e "${YELLOW}Exporting for Docker Compose:${NC}"
            echo "# Decrypt to .env:"
            echo "$0 decrypt $target_version > .env"
            ;;
    esac
}

# Check dependencies first
check_dependencies

# Main command handling
case "${1:-}" in
    "setup")
        setup_encryption
        ;;
    "backup")
        backup_env "$2"
        ;;
    "list")
        list_versions
        ;;
    "rollback")
        rollback_env "$2"
        ;;
    "current")
        show_current
        ;;
    "diff")
        diff_env "$2"
        ;;
    "decrypt")
        decrypt_version "$2"
        ;;
    "export")
        export_env "$2" "$3"
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac