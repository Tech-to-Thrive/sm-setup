#!/bin/bash
# Stack Masters Setup Script - Universal Setup for macOS and Linux
# 
# USAGE: Always run without sudo: ./setup-mac-linux.sh
#        The script will auto-elevate on Linux if needed
#
# Supports: macOS, Ubuntu 20.04+, Debian 10+, RHEL 8+, CentOS 8+, AlmaLinux 8+

set -euo pipefail

# Script version
VERSION="1.0.0"

# Parse command line arguments
DEPLOYMENT_MODE=""
SKIP_FIREWALL=false
SKIP_AUTH=false
REPO_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            DEPLOYMENT_MODE="1"
            shift
            ;;
        --local|--development)
            DEPLOYMENT_MODE="2"
            shift
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        --skip-auth)
            SKIP_AUTH=true
            shift
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --help)
            echo "Stack Masters Setup Script v$VERSION"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "IMPORTANT: Always run WITHOUT sudo. The script will auto-elevate on Linux."
            echo ""
            echo "Options:"
            echo "  --server          Server deployment mode (configure firewall)"
            echo "  --local           Local development mode (skip firewall)"
            echo "  --development     Same as --local"
            echo "  --skip-firewall   Skip firewall configuration entirely"
            echo "  --skip-auth       Skip GitHub authentication (for testing)"
            echo "  --repo-url URL    GitHub repository URL to clone"
            echo "  --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Interactive mode (default)"
            echo "  $0 --server       # Server deployment, no prompts"
            echo "  $0 --local        # Local development, no prompts"
            echo ""
            echo "The script automatically detects your OS and:"
            echo "  - macOS: Runs without sudo (Homebrew doesn't need root)"
            echo "  - Linux: Auto-elevates to sudo if needed"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize logging
LOG_DIR="${PWD}/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/stack-masters-logs"
LOG_FILE="$LOG_DIR/stack-masters-setup-$(date +%Y%m%d-%H%M%S).log"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE" 2>/dev/null
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null
}

# Early OS detection (minimal, just for elevation decision)
early_detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

# Auto-elevate for Linux if not root
auto_elevate() {
    local os_type=$(early_detect_os)
    
    if [[ "$os_type" == "linux" ]] && [[ $EUID -ne 0 ]]; then
        log_info "Linux detected. This script requires root privileges."
        log_info "Re-running with sudo..."
        echo ""
        exec sudo "$0" "$@"
        exit $?
    fi
    
    if [[ "$os_type" == "macos" ]]; then
        log_info "macOS detected - running without sudo (Homebrew doesn't require root)"
    fi
}

# Detect OS and package manager
detect_os() {
    log_info "Detecting operating system..."
    
    # Check for macOS first
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        OS_VERSION=$(sw_vers -productVersion)
        OS_NAME="macOS $(sw_vers -productName) $OS_VERSION"
        
        # Check for Homebrew
        if command -v brew &> /dev/null; then
            PKG_MANAGER="brew"
            PKG_UPDATE="brew update"
            PKG_INSTALL="brew install"
        else
            log_error "Homebrew not found. Please install Homebrew first:"
            log_info "Visit: https://brew.sh or run:"
            log_info '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            exit 1
        fi
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        # Handle distributions without VERSION_ID (like Arch)
        if [ -z "${VERSION_ID:-}" ]; then
            OS_VERSION="${BUILD_ID:-unknown}"
        else
            OS_VERSION=$VERSION_ID
        fi
        OS_NAME=$PRETTY_NAME
    else
        log_error "Cannot detect OS. Neither macOS nor Linux with /etc/os-release found."
        exit 1
    fi
    
    # Detect package manager for Linux (macOS already handled above)
    if [[ "$OS" != "macos" ]]; then
        if command -v apt-get &> /dev/null; then
            PKG_MANAGER="apt"
            PKG_UPDATE="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update -y"
            PKG_INSTALL="yum install -y"
        elif command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf update -y"
            PKG_INSTALL="dnf install -y"
        elif command -v pacman &> /dev/null; then
            PKG_MANAGER="pacman"
            PKG_UPDATE="pacman -Sy --noconfirm"
            PKG_INSTALL="pacman -S --noconfirm"
        elif command -v zypper &> /dev/null; then
            PKG_MANAGER="zypper"
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
        else
            log_error "No supported package manager found (apt, yum, dnf, pacman, zypper)"
            exit 1
        fi
    fi
    
    log_success "Detected: $OS_NAME"
    log_success "Package manager: $PKG_MANAGER"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    if [[ "$OS" == "macos" ]]; then
        # Homebrew update doesn't need sudo
        brew update
    else
        $PKG_UPDATE
    fi
    log_success "System packages updated"
}

# Install core dependencies
install_core_deps() {
    log_info "Installing core dependencies..."
    
    # Common packages across distributions
    CORE_PACKAGES="curl wget ca-certificates gnupg"
    
    # Distribution-specific adjustments
    case $PKG_MANAGER in
        brew)
            # macOS with Homebrew - most are already included
            CORE_PACKAGES="wget gnupg"
            ;;
        apt)
            CORE_PACKAGES="$CORE_PACKAGES apt-transport-https lsb-release software-properties-common"
            ;;
        yum|dnf)
            CORE_PACKAGES="$CORE_PACKAGES yum-utils"
            ;;
        pacman)
            CORE_PACKAGES="$CORE_PACKAGES base-devel"
            ;;
        zypper)
            CORE_PACKAGES="$CORE_PACKAGES patterns-devel-base-devel_basis"
            ;;
    esac
    
    $PKG_INSTALL $CORE_PACKAGES
    log_success "Core dependencies installed"
}

# Install Git
install_git() {
    log_info "Installing Git..."
    
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        log_info "Git already installed: version $GIT_VERSION"
    else
        $PKG_INSTALL git
        log_success "Git installed successfully"
    fi
}

# Install GitHub CLI
install_github_cli() {
    log_info "Installing GitHub CLI..."
    
    if command -v gh &> /dev/null; then
        GH_VERSION=$(gh --version | head -n1 | awk '{print $3}')
        log_info "GitHub CLI already installed: version $GH_VERSION"
        return
    fi
    
    case $PKG_MANAGER in
        brew)
            brew install gh
            ;;
        apt)
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            apt-get update
            apt-get install gh -y
            ;;
        yum|dnf)
            dnf install 'dnf-command(config-manager)' -y 2>/dev/null || true
            dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo -y
            dnf install gh -y
            ;;
        pacman)
            pacman -S github-cli --noconfirm
            ;;
        zypper)
            # GitHub CLI not in standard repos, install from releases
            curl -fsSL https://github.com/cli/cli/releases/download/v2.40.1/gh_2.40.1_linux_amd64.tar.gz | tar -xz
            mv gh_2.40.1_linux_amd64/bin/gh /usr/local/bin/
            rm -rf gh_2.40.1_linux_amd64
            ;;
    esac
    
    log_success "GitHub CLI installed successfully"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,$//')
        log_info "Docker already installed: version $DOCKER_VERSION"
        return
    fi
    
    case $PKG_MANAGER in
        brew)
            log_info "Installing Docker Desktop for macOS..."
            brew install --cask docker
            log_warning "Docker Desktop needs to be started manually from Applications"
            log_info "Please start Docker Desktop and wait for it to initialize before continuing"
            read -p "Press Enter when Docker Desktop is running..."
            ;;
        apt)
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add the repository to Apt sources
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            apt-get update
            apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
            ;;
        yum|dnf)
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo -y
            dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
            ;;
        pacman)
            pacman -S docker docker-compose --noconfirm
            ;;
        zypper)
            zypper install docker docker-compose -y
            ;;
    esac
    
    # Start and enable Docker (skip for macOS as Docker Desktop handles this)
    if [[ "$OS" != "macos" ]]; then
        systemctl start docker
        systemctl enable docker
    fi
    
    log_success "Docker installed and started successfully"
}

# Configure firewall rules
configure_firewall() {
    # Skip firewall configuration for macOS
    if [[ "$OS" == "macos" ]]; then
        log_info "macOS detected - skipping firewall configuration"
        log_info "macOS firewall can be configured in System Preferences if needed"
        return
    fi
    
    if [ "$SKIP_FIREWALL" = true ]; then
        log_info "Skipping firewall configuration (--skip-firewall flag)"
        return
    fi
    
    # Use command line argument if provided, otherwise prompt
    if [ -z "$DEPLOYMENT_MODE" ]; then
        log_info "Deployment Mode Selection"
        echo ""
        echo "Please select your deployment type:"
        echo "1) Server deployment (VPS/Cloud) - Configure firewall with required ports"
        echo "2) Local development (Mac/Windows/Linux) - Skip firewall configuration"
        echo ""
        read -p "Select mode [1-2] (default: 1): " DEPLOYMENT_MODE
        
        # Default to server mode if no input
        DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-1}
    fi
    
    case $DEPLOYMENT_MODE in
        1)
            log_info "Server deployment mode selected - configuring firewall..."
            configure_server_firewall
            ;;
        2)
            log_info "Local development mode selected - skipping firewall configuration"
            log_info "Assuming local firewall/router handles port access"
            return
            ;;
        *)
            log_error "Invalid selection. Defaulting to server deployment mode."
            configure_server_firewall
            ;;
    esac
}

# Configure firewall for server deployment
configure_server_firewall() {
    # Open all required ports for server deployment
    PORTS=(
        "80:tcp"      # HTTP (Nginx proxy)
        "443:tcp"     # HTTPS (Nginx proxy)
        "8080:tcp"    # Alternative HTTP port
        "3000:tcp"    # Grafana
        "3001:tcp"    # Stack Manager UI
        "3002:tcp"    # Stack Manager API
        "5678:tcp"    # n8n
        "9090:tcp"    # Prometheus
        "9999:tcp"    # Auth proxy
        "587:tcp"     # SMTP Submission (secure outbound email)
        "465:tcp"     # SMTPS (secure outbound email SSL/TLS)
    )
    
    log_info "Opening ports for Stack Masters services and web access"
    
    # Detect firewall
    if command -v ufw &> /dev/null; then
        log_info "Configuring UFW firewall..."
        ufw --force enable
        for port in "${PORTS[@]}"; do
            port_num=$(echo $port | cut -d: -f1)
            proto=$(echo $port | cut -d: -f2)
            ufw allow $port_num/$proto
            log_info "Allowed port $port_num/$proto"
        done
        # Allow SSH if not already allowed
        ufw allow 22/tcp
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        log_info "Configuring firewalld..."
        systemctl start firewalld
        systemctl enable firewalld
        for port in "${PORTS[@]}"; do
            firewall-cmd --permanent --add-port=$port
            log_info "Allowed port $port"
        done
        # Allow SSH
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
    else
        log_warning "No firewall detected. Please manually configure firewall rules for ports: ${PORTS[*]}"
    fi
    
    log_success "Firewall configuration complete"
}

# GitHub authentication
github_auth() {
    if [ "$SKIP_AUTH" = true ]; then
        log_info "Skipping GitHub authentication (--skip-auth flag used)"
        return
    fi
    
    log_info "Setting up GitHub authentication..."
    
    # Check if already authenticated
    if gh auth status &> /dev/null; then
        log_success "GitHub CLI already authenticated"
        # Show which account is logged in
        local current_user=$(gh api user --jq .login 2>/dev/null)
        if [ -n "$current_user" ]; then
            log_info "Logged in as: $current_user"
        fi
        return
    fi
    
    echo ""
    log_info "GitHub authentication required for repository access"
    
    # Detect server environment (SSH, no display, or --server flag)
    if [[ -n "${SSH_CONNECTION:-}" ]] || [[ -z "${DISPLAY:-}" ]] || [[ "$DEPLOYMENT_MODE" == "1" ]]; then
        log_info "Server environment detected - using device code authentication"
        echo ""
        echo "=========================================="
        log_info "GITHUB AUTHENTICATION REQUIRED"
        echo "=========================================="
        echo ""
        log_info "1. GitHub will display a device code below"
        log_info "2. Copy the device code"
        log_info "3. Visit: https://github.com/login/device"
        log_info "4. Paste the code and complete authentication"
        echo ""
        echo "Starting GitHub authentication..."
        echo ""
        
        gh auth login
    else
        log_info "Desktop environment detected - opening browser for authentication"
        log_info "If browser doesn't open, you'll see a device code to enter at: https://github.com/login/device"
        echo ""
        
        # Try browser auth first, fallback to device code
        if ! timeout 30 gh auth login --web 2>/dev/null; then
            log_info "Browser authentication failed or timed out, using device code flow..."
            gh auth login
        fi
    fi
    
    if gh auth status &> /dev/null; then
        log_success "GitHub authentication successful"
    else
        log_error "GitHub authentication failed"
        exit 1
    fi
}

# Get repository URL
get_repository_url() {
    if [ -n "$REPO_URL" ]; then
        echo "$REPO_URL"
        return
    fi
    
    # Display to stderr so it shows even when captured
    {
        echo ""
        echo "=========================================="
        log_info "REPOSITORY SETUP"
        echo "=========================================="
        echo ""
        echo "Please provide the GitHub repository URL to clone."
        echo ""
        log_warning "Note: You must be a member of the Skool community to access these repos"
        echo ""
        echo -e "${GREEN}Examples:${NC}"
        echo ""
        echo -e "${YELLOW}  1. https://github.com/AI-Stack-Master-Pros/stack-pro${NC}"
        echo -e "     ${BLUE}(Requires membership: https://www.skool.com/ai-stack-master-pros)${NC}"
        echo ""
        echo -e "${YELLOW}  2. https://github.com/AI-Stack-Masters/stack-community${NC}"
        echo -e "     ${BLUE}(Requires membership: https://www.skool.com/ai-stack-masters)${NC}"
        echo ""
        echo "=========================================="
        echo ""
    } >&2
    
    read -p "$(echo -e ${GREEN}Repository URL: ${NC})" url
    echo "$url"
}

# Clone appropriate repository
clone_repository() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        REPO_URL=$(get_repository_url)
        
        # Validate URL format
        if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]]; then
            log_error "Invalid GitHub repository URL format"
            log_info "Expected format: https://github.com/owner/repository"
            if [ $attempt -lt $max_attempts ]; then
                echo ""
                log_warning "Please try again (Attempt $attempt of $max_attempts)"
                ((attempt++))
                continue
            else
                log_error "Maximum attempts reached. Exiting."
                exit 1
            fi
        fi
        
        # Extract repository name from URL
        REPO_NAME=$(basename "$REPO_URL" .git)
        REPO_OWNER=$(echo "$REPO_URL" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
        REPO_PATH="$REPO_OWNER/$REPO_NAME"
        
        log_info "Repository: $REPO_PATH"
        
        # Check if user has access to the repository
        if gh repo view "$REPO_PATH" &> /dev/null; then
            log_success "Access to $REPO_NAME confirmed!"
            break
        else
            log_error "Cannot access repository: $REPO_PATH"
            log_info "Please ensure:"
            echo "  1. You have access to this repository"
            echo "  2. You are a member of the required Skool community"
            echo "  3. Your GitHub authentication is working (gh auth status)"
            
            if [ $attempt -lt $max_attempts ]; then
                echo ""
                log_warning "Please try again with a different URL (Attempt $attempt of $max_attempts)"
                ((attempt++))
            else
                log_error "Maximum attempts reached. Exiting."
                exit 1
            fi
        fi
    done
    
    # Set clone directory based on OS
    if [[ "$OS" == "macos" ]]; then
        # Use user's home directory for macOS
        CLONE_DIR="$HOME/stack-masters/$REPO_NAME"
        mkdir -p "$HOME/stack-masters"
    else
        # Use /opt for Linux
        CLONE_DIR="/opt/$REPO_NAME"
    fi
    
    # Handle existing directory
    if [ -d "$CLONE_DIR" ]; then
        log_warning "Directory $CLONE_DIR already exists."
        echo ""
        echo "What would you like to do?"
        echo "  1. Delete existing directory and clone fresh (recommended)"
        echo "  2. Keep existing directory and skip cloning"
        echo "  3. Cancel"
        echo ""
        read -p "Select option [1-3] (default: 1): " choice
        choice=${choice:-1}
        
        case $choice in
            1)
                log_info "Removing existing directory..."
                rm -rf "$CLONE_DIR"
                log_success "Existing directory removed"
                ;;
            2)
                log_info "Keeping existing directory. Skipping clone."
                export STACK_DIR=$CLONE_DIR
                return
                ;;
            3)
                log_info "Clone cancelled by user"
                exit 0
                ;;
            *)
                log_info "Invalid choice. Using existing directory."
                export STACK_DIR=$CLONE_DIR
                return
                ;;
        esac
    fi
    
    # Clone the repository
    log_info "Cloning repository: $REPO_PATH"
    gh repo clone "$REPO_PATH" "$CLONE_DIR"
    
    log_success "Repository cloned to: $CLONE_DIR"
    
    # Export for use in subsequent scripts
    export STACK_DIR=$CLONE_DIR
}

# System validation
validate_system() {
    log_info "Validating system configuration..."
    
    # Check Docker
    if docker run --rm hello-world &> /dev/null; then
        log_success "Docker is working correctly"
    else
        log_warning "Docker is installed but not running"
        echo ""
        
        # Try to start Docker
        if [[ "$OS" == "macos" ]]; then
            # macOS - try to start Docker Desktop
            if [ -d "/Applications/Docker.app" ]; then
                log_info "Attempting to start Docker Desktop..."
                open -a Docker
                
                echo "Waiting for Docker to start (this may take a minute)..."
                local attempts=0
                local max_attempts=30
                
                while [ $attempts -lt $max_attempts ]; do
                    sleep 1
                    ((attempts++))
                    
                    if docker ps &> /dev/null; then
                        log_success "Docker started successfully!"
                        return
                    fi
                    
                    if [ $((attempts % 5)) -eq 0 ]; then
                        echo "Still waiting for Docker to start... ($attempts seconds)"
                    fi
                done
            fi
            
            # Docker didn't start automatically
            log_warning "Docker Desktop needs to be running"
            echo ""
            echo "Options:"
            echo "  1. I'll start Docker manually (retry after starting)"
            echo "  2. Continue without Docker (WARNING: Stack will not function)"
            echo "  3. Cancel installation"
            echo ""
            
            read -p "Select option [1-3] (default: 1): " choice
            choice=${choice:-1}
            
            case $choice in
                1)
                    log_info "Please start Docker Desktop manually"
                    echo "  1. Open Docker Desktop from Applications"
                    echo "  2. Wait for Docker to fully start (menu bar icon)"
                    echo "  3. Press Enter when ready to continue"
                    read -p ""
                    
                    # Test again
                    if docker ps &> /dev/null; then
                        log_success "Docker is now running!"
                    else
                        log_error "Docker still not responding. Please ensure Docker Desktop is running."
                        exit 1
                    fi
                    ;;
                2)
                    log_warning "Continuing without Docker. Stack Masters will not function!"
                    ;;
                3)
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
                *)
                    log_info "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        else
            # Linux - try to start Docker service
            log_info "Attempting to start Docker service..."
            if sudo systemctl start docker &> /dev/null; then
                sleep 2
                if docker ps &> /dev/null; then
                    log_success "Docker service started successfully!"
                    return
                fi
            fi
            
            # Docker service didn't start
            log_warning "Docker service needs to be running"
            echo ""
            echo "Options:"
            echo "  1. Try to start Docker service again"
            echo "  2. Continue without Docker (WARNING: Stack will not function)"
            echo "  3. Cancel installation"
            echo ""
            
            read -p "Select option [1-3] (default: 1): " choice
            choice=${choice:-1}
            
            case $choice in
                1)
                    log_info "Please run: sudo systemctl start docker"
                    echo "Press Enter when Docker is running..."
                    read -p ""
                    
                    # Test again
                    if docker ps &> /dev/null; then
                        log_success "Docker is now running!"
                    else
                        log_error "Docker still not responding. Please ensure Docker is running."
                        exit 1
                    fi
                    ;;
                2)
                    log_warning "Continuing without Docker. Stack Masters will not function!"
                    ;;
                3)
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
                *)
                    log_info "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        fi
    fi
    
    # Check disk space
    if [[ "$OS" == "macos" ]]; then
        # macOS df output is different
        AVAILABLE_SPACE=$(df -g "$HOME" | tail -1 | awk '{print $4}')
    else
        AVAILABLE_SPACE=$(df -BG /opt | tail -1 | awk '{print $4}' | sed 's/G//')
    fi
    
    if [ "$AVAILABLE_SPACE" -lt 20 ]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available (recommended: 20GB+)"
    else
        log_success "Disk space adequate: ${AVAILABLE_SPACE}GB available"
    fi
    
    # Check memory
    if [[ "$OS" == "macos" ]]; then
        # macOS doesn't have 'free' command, use sysctl
        TOTAL_MEM_BYTES=$(sysctl -n hw.memsize)
        TOTAL_MEM=$((TOTAL_MEM_BYTES / 1073741824))  # Convert to GB
    else
        TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    fi
    
    if [ "$TOTAL_MEM" -lt 4 ]; then
        log_warning "Low memory: ${TOTAL_MEM}GB available (recommended: 4GB+)"
    else
        log_success "Memory adequate: ${TOTAL_MEM}GB available"
    fi
}

# Check Docker status
check_docker_status() {
    if ! command -v docker &> /dev/null; then
        echo "not_installed"
        return
    fi
    
    if docker ps &> /dev/null; then
        echo "running"
    else
        echo "not_running"
    fi
}

# Display installation summary
show_summary() {
    clear
    echo "=============================================="
    echo "   Stack Masters Installation Summary"
    echo "=============================================="
    echo ""
    
    local install_success=true
    local docker_ready=false
    
    echo -e "${BLUE}Installation Results:${NC}"
    echo ""
    
    # Check each component
    if command -v git &> /dev/null; then
        echo -e "  ${GREEN}[OK] Git: $(git --version 2>/dev/null | awk '{print $3}')${NC}"
    else
        echo -e "  ${RED}[FAIL] Git: Installation failed${NC}"
        install_success=false
    fi
    
    if command -v gh &> /dev/null; then
        echo -e "  ${GREEN}[OK] GitHub CLI: Installed${NC}"
        if [ "$SKIP_AUTH" != "true" ] && gh auth status &> /dev/null; then
            local current_user=$(gh api user --jq .login 2>/dev/null)
            if [ -n "$current_user" ]; then
                echo -e "  ${GREEN}[OK] GitHub Auth: Logged in as $current_user${NC}"
            fi
        elif [ "$SKIP_AUTH" != "true" ]; then
            echo -e "  ${YELLOW}[WARN] GitHub Auth: Not authenticated${NC}"
        fi
    else
        echo -e "  ${RED}[FAIL] GitHub CLI: Installation failed${NC}"
        install_success=false
    fi
    
    # Check Docker
    local docker_status=$(check_docker_status)
    if [ "$docker_status" = "running" ]; then
        echo -e "  ${GREEN}[OK] Docker: Running and ready${NC}"
        docker_ready=true
    elif [ "$docker_status" = "not_running" ]; then
        echo -e "  ${YELLOW}[WARN] Docker: Installed but not running${NC}"
        if [[ "$OS" == "macos" ]]; then
            echo "        Please start Docker Desktop from Applications"
        else
            echo "        Run: sudo systemctl start docker"
        fi
    else
        echo -e "  ${YELLOW}[WARN] Docker: Not installed${NC}"
    fi
    
    if [ -n "$STACK_DIR" ] && [ -d "$STACK_DIR" ]; then
        echo -e "  ${GREEN}[OK] Repository: Cloned to $STACK_DIR${NC}"
    elif [ -n "$STACK_DIR" ]; then
        echo -e "  ${RED}[FAIL] Repository: Clone failed${NC}"
        install_success=false
    fi
    
    echo ""
    
    # Check system resources
    echo -e "${BLUE}System Resources:${NC}"
    if [[ "$OS" == "macos" ]]; then
        local free_space=$(df -g "$HOME" | tail -1 | awk '{print $4}')
        local total_mem=$(($(sysctl -n hw.memsize) / 1073741824))
    else
        local free_space=$(df -BG /opt 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
        local total_mem=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
    fi
    
    if [ "$free_space" -ge 20 ]; then
        echo -e "  ${GREEN}[OK] Disk Space: ${free_space}GB available${NC}"
    else
        echo -e "  ${YELLOW}[WARN] Disk Space: ${free_space}GB (recommended: 20GB+)${NC}"
    fi
    
    if [ "$total_mem" -ge 4 ]; then
        echo -e "  ${GREEN}[OK] Memory: ${total_mem}GB${NC}"
    else
        echo -e "  ${YELLOW}[WARN] Memory: ${total_mem}GB (recommended: 4GB+)${NC}"
    fi
    
    echo ""
    echo "=============================================="
    
    # Next steps
    if [ "$install_success" = true ] && [ -n "$STACK_DIR" ] && [ -d "$STACK_DIR" ]; then
        local env_script="$STACK_DIR/deploy/scripts/generate-env-config.sh"
        
        if [ -f "$env_script" ]; then
            if [ "$docker_ready" = true ]; then
                echo ""
                log_success "All components installed successfully!"
                echo ""
                log_info "Starting environment configuration..."
                echo "Running: generate-env-config.sh"
                echo ""
                echo "=============================================="
                echo ""
                
                # Change to the repository directory and run the script
                cd "$STACK_DIR" && bash "$env_script"
            else
                echo ""
                log_warning "Installation complete but Docker is not running"
                echo ""
                log_info "Next steps:"
                echo "  1. Start Docker"
                if [[ "$OS" == "macos" ]]; then
                    echo "     - Open Docker Desktop from Applications"
                else
                    echo "     - Run: sudo systemctl start docker"
                fi
                echo "  2. Run environment setup:"
                echo "     cd $STACK_DIR"
                echo "     ./deploy/scripts/generate-env-config.sh"
            fi
        else
            echo ""
            log_success "Installation completed!"
            echo ""
            log_info "Next steps:"
            echo "  1. Navigate to: cd $STACK_DIR"
            echo "  2. Check the repository README for setup instructions"
        fi
    else
        echo ""
        log_error "Some components failed to install"
        echo ""
        log_info "Please check the log file for details: $LOG_FILE"
        echo ""
        echo "Try running the script again after addressing any errors."
    fi
    
    echo ""
    echo "=============================================="
    echo ""
    log_info "Log file: $LOG_FILE"
}

# Main installation flow
main() {
    clear
    
    # Setup type is always localhost
    local setup_type="Local Development Setup"
    
    echo "=============================================="
    echo "   Stack Masters Setup Script v${VERSION}"
    echo "   $setup_type"
    echo "=============================================="
    echo ""
    
    # Auto-elevate if needed (must be before any operations)
    auto_elevate "$@"
    
    # Now do full OS detection
    detect_os
    
    # Check what's already installed
    echo ""
    log_info "Checking existing installations..."
    echo ""
    
    local git_installed=$(command -v git &> /dev/null && echo "yes" || echo "no")
    local gh_installed=$(command -v gh &> /dev/null && echo "yes" || echo "no")
    local docker_status=$(check_docker_status)
    local gh_authenticated="no"
    
    if [ "$gh_installed" = "yes" ] && [ "$SKIP_AUTH" != "true" ]; then
        gh auth status &> /dev/null && gh_authenticated="yes"
    fi
    
    # Build list of what needs to be done
    local needs_install=()
    local already_installed=()
    
    if [ "$git_installed" = "yes" ]; then
        already_installed+=("[OK] Git: $(git --version 2>/dev/null | awk '{print $3}')")
    else
        needs_install+=("- Git")
    fi
    
    if [ "$gh_installed" = "yes" ]; then
        already_installed+=("[OK] GitHub CLI")
    else
        needs_install+=("- GitHub CLI")
    fi
    
    if [ "$docker_status" = "running" ]; then
        already_installed+=("[OK] Docker: Running")
    elif [ "$docker_status" = "not_running" ]; then
        already_installed+=("[OK] Docker: Installed but not running")
    else
        needs_install+=("- Docker")
    fi
    
    # Show status
    if [ ${#already_installed[@]} -gt 0 ]; then
        echo -e "${GREEN}Already Installed:${NC}"
        for item in "${already_installed[@]}"; do
            echo -e "  ${GREEN}$item${NC}"
        done
        echo ""
    fi
    
    echo -e "${BLUE}This script will perform the following:${NC}"
    echo ""
    deployment_text="Local Development (default)"
    [ "$DEPLOYMENT_MODE" = "1" ] && deployment_text="Server Deployment"
    echo -e "  ${YELLOW}DEPLOYMENT MODE: $deployment_text${NC}"
    echo ""
    
    if [ ${#needs_install[@]} -gt 0 ]; then
        echo "  Software to Install:"
        for item in "${needs_install[@]}"; do
            echo "    $item"
        done
        echo ""
    else
        echo -e "  ${GREEN}All required software is already installed!${NC}"
        echo ""
    fi
    
    echo "  System Configuration:"
    if [ "$DEPLOYMENT_MODE" = "1" ]; then
        echo "     - Configure firewall (ports: 80, 443, 8080, etc.)"
    else
        echo "     - Skip firewall configuration (Local mode)"
    fi
    echo ""
    
    echo "  GitHub Setup:"
    if [ "$SKIP_AUTH" != "true" ]; then
        if [ "$gh_authenticated" = "yes" ]; then
            echo -e "     ${GREEN}[OK] Already authenticated with GitHub${NC}"
        else
            echo "     - Authenticate with GitHub"
        fi
    fi
    echo "     - Clone repository to ./stack-masters/"
    echo ""
    
    echo "  Final Steps:"
    echo "     - Validate installation"
    echo "     - Check system resources"
    echo ""
    
    # Get confirmation
    echo -e "${YELLOW}Do you want to proceed with the installation?${NC}"
    read -p "Type 'yes' to continue or anything else to exit: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_warning "Installation cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Starting Stack Masters setup..."
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # System preparation
    update_system
    install_core_deps
    
    # Install components
    install_git
    install_github_cli
    install_docker
    
    # Configure system
    configure_firewall
    
    # GitHub authentication and repository setup
    github_auth
    clone_repository
    
    # Validate installation
    validate_system
    
    # Show summary
    show_summary
}

# Run main function
main "$@"