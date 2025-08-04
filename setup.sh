#!/bin/bash
# Stack Masters Setup Script - Universal Linux Server Provisioning
# This script prepares a fresh Linux VPS/server for Stack Masters deployment
# Works with: Hostinger, DigitalOcean, Vultr, AWS EC2, Linode, or any Linux VPS
# Supports: Ubuntu 20.04+, Debian 10+, RHEL 8+, CentOS 8+, AlmaLinux 8+

set -euo pipefail

# Script version
VERSION="1.0.0"

# Parse command line arguments
DEPLOYMENT_MODE=""
SKIP_FIREWALL=false

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
        --help)
            echo "Stack Masters Setup Script v$VERSION"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --server          Server deployment mode (configure firewall)"
            echo "  --local           Local development mode (skip firewall)"
            echo "  --development     Same as --local"
            echo "  --skip-firewall   Skip firewall configuration entirely"
            echo "  --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Auto-detect based on OS type"
            echo "  $0 --server       # Force server deployment mode"
            echo "  $0 --local        # Force local development mode"
            echo ""
            echo "Automatic behavior:"
            echo "  - Server OS: Configures firewall for server deployment"
            echo "  - Desktop OS: Skips firewall configuration (local development)"
            echo "  - Use --server or --local flags to override automatic detection"
            echo ""
            echo "Repository access requires Skool community membership:"
            echo "  - AI Stack Masters (Free): https://www.skool.com/ai-stack-masters"
            echo "  - AI Stack Master Pros (Paid): https://www.skool.com/ai-stack-master-pros"
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

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Detect OS type (server vs desktop)
detect_os_type() {
    # Check if this is a server or desktop environment
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # Check for desktop indicators
        if [ -n "${DESKTOP_SESSION:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ] || [ -n "${DISPLAY:-}" ]; then
            echo "desktop"
        elif [[ "$NAME" =~ "Server" ]] || [ -z "${DISPLAY:-}" ]; then
            echo "server"
        else
            # Default to desktop for unknown environments
            echo "desktop"
        fi
    else
        echo "server"  # Default to server if we can't detect
    fi
}

# Detect OS and package manager
detect_os() {
    log_info "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
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
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    # Detect package manager
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
    
    # Detect OS type
    OS_TYPE=$(detect_os_type)
    
    log_success "Detected: $OS_NAME"
    log_success "OS Type: $OS_TYPE"
    log_success "Package manager: $PKG_MANAGER"
}

# Check installed packages
check_system_packages() {
    log_info "Checking system packages..."
    echo ""
    
    local installed_packages=()
    local missing_packages=()
    
    # Check Git
    log_info "Checking Git..."
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        installed_packages+=("✓ Git - version $GIT_VERSION")
        GIT_INSTALLED=true
    else
        missing_packages+=("✗ Git - Version control system")
        GIT_INSTALLED=false
    fi
    
    # Check GitHub CLI
    log_info "Checking GitHub CLI..."
    if command -v gh &> /dev/null; then
        GH_VERSION=$(gh --version | head -n1 | awk '{print $3}')
        installed_packages+=("✓ GitHub CLI - version $GH_VERSION")
        GH_INSTALLED=true
    else
        missing_packages+=("✗ GitHub CLI - Required for repository authentication")
        GH_INSTALLED=false
    fi
    
    # Check Docker
    log_info "Checking Docker..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,$//')
        installed_packages+=("✓ Docker - version $DOCKER_VERSION")
        DOCKER_INSTALLED=true
    else
        missing_packages+=("✗ Docker - Container runtime")
        DOCKER_INSTALLED=false
    fi
    
    # Display results
    echo ""
    echo -e "${BLUE}System Package Status:${NC}"
    echo -e "${BLUE}=====================${NC}"
    
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Installed packages:${NC}"
        for package in "${installed_packages[@]}"; do
            echo -e "  ${GREEN}$package${NC}"
        done
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Missing packages:${NC}"
        for package in "${missing_packages[@]}"; do
            echo -e "  ${YELLOW}$package${NC}"
        done
    fi
    
    echo ""
}

# Confirm installation
confirm_installation() {
    local needs_installation=false
    local install_list=()
    
    if [ "$GIT_INSTALLED" = false ]; then
        needs_installation=true
        install_list+=("- Git")
    fi
    
    if [ "$GH_INSTALLED" = false ]; then
        needs_installation=true
        install_list+=("- GitHub CLI")
    fi
    
    if [ "$DOCKER_INSTALLED" = false ]; then
        needs_installation=true
        install_list+=("- Docker")
    fi
    
    if [ "$needs_installation" = false ]; then
        log_success "All required packages are already installed!"
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}The following packages will be installed:${NC}"
    for item in "${install_list[@]}"; do
        echo -e "  ${YELLOW}$item${NC}"
    done
    
    echo ""
    echo -ne "${BLUE}Do you want to proceed with the installation? (Y/N) ${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy](es)?$ ]]; then
        echo ""
        log_info "Proceeding with installation..."
        return 0
    else
        log_warning "Installation cancelled by user"
        return 1
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    $PKG_UPDATE
    log_success "System packages updated"
}

# Install core dependencies
install_core_deps() {
    log_info "Installing core dependencies..."
    
    # Common packages across distributions
    CORE_PACKAGES="curl wget ca-certificates gnupg"
    
    # Distribution-specific adjustments
    case $PKG_MANAGER in
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
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker installed and started successfully"
}

# Configure firewall rules
configure_firewall() {
    if [ "$SKIP_FIREWALL" = true ]; then
        log_info "Skipping firewall configuration (--skip-firewall flag)"
        return
    fi
    
    # Check if user explicitly specified a mode
    local force_server_mode=false
    local force_local_mode=false
    
    if [ "$DEPLOYMENT_MODE" = "1" ]; then
        force_server_mode=true
    elif [ "$DEPLOYMENT_MODE" = "2" ]; then
        force_local_mode=true
    fi
    
    # Determine action based on OS type and user parameters
    if [ "$OS_TYPE" = "server" ] && [ "$force_local_mode" = false ]; then
        # Server OS - configure firewall unless explicitly set to local mode
        log_info "Server OS detected - configuring firewall for server deployment..."
        configure_server_firewall
    elif [ "$OS_TYPE" = "desktop" ] && [ "$force_server_mode" = false ]; then
        # Desktop OS - skip firewall unless explicitly set to server mode
        log_info "Desktop OS detected - skipping firewall configuration for local development"
        log_info "Firewall configuration is not needed for local development environments"
    elif [ "$force_server_mode" = true ]; then
        # User explicitly wants server mode on desktop
        log_warning "Server mode forced on desktop OS - configuring firewall..."
        configure_server_firewall
    elif [ "$force_local_mode" = true ]; then
        # User explicitly wants local mode on server
        log_warning "Local mode forced on server OS - skipping firewall configuration"
        log_info "Firewall configuration skipped by user request"
    fi
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
    log_info "Setting up GitHub authentication..."
    
    # Check if already authenticated
    if gh auth status &> /dev/null; then
        log_success "GitHub CLI already authenticated"
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

# Setup provisioning wizard
setup_provisioning_wizard() {
    log_info "Setting up Stack Masters Provisioning Wizard..."
    
    # Get the script's directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Source provisioning-web is included in this repository
    SOURCE_WIZARD_DIR="$SCRIPT_DIR/apps/provisioning-web"
    
    # Target directory for the wizard
    TARGET_WIZARD_DIR="/opt/stack-masters-wizard"
    
    if [ ! -d "$SOURCE_WIZARD_DIR" ]; then
        log_error "Provisioning wizard source not found at: $SOURCE_WIZARD_DIR"
        exit 1
    fi
    
    # Create target directory parent if needed
    mkdir -p "$(dirname "$TARGET_WIZARD_DIR")"
    
    if [ -d "$TARGET_WIZARD_DIR" ]; then
        log_warning "Directory $TARGET_WIZARD_DIR already exists. Backing up..."
        mv "$TARGET_WIZARD_DIR" "${TARGET_WIZARD_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    log_info "Copying provisioning wizard to $TARGET_WIZARD_DIR..."
    if cp -r "$SOURCE_WIZARD_DIR" "$TARGET_WIZARD_DIR"; then
        log_success "Provisioning wizard copied successfully"
    else
        log_error "Failed to copy provisioning wizard"
        exit 1
    fi
    
    # Set global variable for other functions
    WIZARD_DIR="$TARGET_WIZARD_DIR"
}

# Start provisioning wizard
start_provisioning_wizard() {
    log_info "Starting Stack Masters Provisioning Wizard..."
    
    # The wizard directory is already the provisioning-web directory
    if [ ! -d "$WIZARD_DIR" ]; then
        log_error "Provisioning wizard directory not found: $WIZARD_DIR"
        exit 1
    fi
    
    # Check if Node.js is available
    if ! command -v node &> /dev/null; then
        log_info "Node.js not found. Installing Node.js..."
        
        # Install Node.js based on package manager
        case $PKG_MANAGER in
            apt)
                curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
                apt-get install -y nodejs
                ;;
            yum|dnf)
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
                $PKG_INSTALL nodejs
                ;;
            pacman)
                pacman -S nodejs npm --noconfirm
                ;;
            zypper)
                zypper install -y nodejs npm
                ;;
        esac
        
        if ! command -v node &> /dev/null; then
            log_error "Failed to install Node.js"
            exit 1
        fi
    fi
    
    # Navigate to backend directory
    BACKEND_DIR="$WIZARD_DIR/backend"
    if [ ! -d "$BACKEND_DIR" ]; then
        log_error "Backend directory not found: $BACKEND_DIR"
        exit 1
    fi
    
    cd "$BACKEND_DIR"
    
    log_info "Installing dependencies..."
    npm install --production
    
    # Set environment variables
    export PROJECT_ROOT="$CLONE_DIR"
    export PORT="8080"
    export NODE_ENV="production"
    
    log_info "Starting provisioning wizard on port 8080..."
    
    # Start the backend server
    node server-integrated.js &
    WIZARD_PID=$!
    
    # Save PID for potential cleanup
    echo $WIZARD_PID > "$WIZARD_DIR/wizard.pid"
    
    log_info "Provisioning wizard started with PID: $WIZARD_PID"
    log_info "Waiting for server to be ready..."
    sleep 5
    
    # Display access information
    log_success "Provisioning wizard is running!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Stack Masters Provisioning Wizard${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Access the wizard at:${NC}"
    echo -e "  ${BLUE}http://localhost:${WIZARD_PORT}${NC}"
    echo ""
    
    # Get server IPs for remote access
    if command -v hostname &> /dev/null; then
        SERVER_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$')
    elif command -v ip &> /dev/null; then
        SERVER_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
    fi
    
    if [ -n "$SERVER_IPS" ]; then
        echo -e "${YELLOW}From a remote machine:${NC}"
        for ip in $SERVER_IPS; do
            echo -e "  ${BLUE}http://${ip}:${WIZARD_PORT}${NC}"
        done
    fi
    echo ""
    echo -e "${YELLOW}The wizard will guide you through:${NC}"
    echo "  - Selecting your Stack Masters repository"
    echo "  - Configuring your environment"
    echo "  - Deploying your services"
    echo ""
}

# Clone appropriate repository (called from wizard)
clone_repository() {
    log_info "Repository Setup"
    echo ""
    echo "Please provide the GitHub repository URL to clone."
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ${BLUE}- https://github.com/AI-Stack-Masters/stack-community${NC}"
    echo -e "  ${BLUE}- https://github.com/AI-Stack-Master-Pros/stack-pro${NC}"
    echo ""
    echo -e "${YELLOW}NOTE: Repository access requires Skool community membership:${NC}"
    echo -e "  - AI Stack Masters (Free):  ${BLUE}https://www.skool.com/ai-stack-masters${NC}"
    echo -e "  - AI Stack Master Pros (Paid): ${BLUE}https://www.skool.com/ai-stack-master-pros${NC}"
    echo ""
    
    read -p "Repository URL: " REPO_URL
    
    # Validate URL format
    if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]]; then
        log_error "Invalid GitHub repository URL format"
        log_info "Expected format: https://github.com/owner/repository"
        exit 1
    fi
    
    # Extract repository name from URL
    REPO_NAME=$(basename "$REPO_URL" .git)
    REPO_OWNER=$(echo "$REPO_URL" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
    REPO_PATH="$REPO_OWNER/$REPO_NAME"
    
    log_info "Repository: $REPO_PATH"
    
    # Check if user has access to the repository
    if gh repo view "$REPO_PATH" &> /dev/null; then
        log_success "Access to $REPO_NAME confirmed!"
    else
        log_error "Cannot access repository: $REPO_PATH"
        log_info "Please ensure you have access to this repository"
        echo ""
        log_warning "Repository access requires Skool community membership:"
        echo -e "  ${YELLOW}- AI Stack Masters (Free): ${BLUE}https://www.skool.com/ai-stack-masters${NC}"
        echo -e "  ${YELLOW}- AI Stack Master Pros (Paid): ${BLUE}https://www.skool.com/ai-stack-master-pros${NC}"
        exit 1
    fi
    
    # Set clone directory
    CLONE_DIR="/opt/$REPO_NAME"
    
    # Remove existing directory if present
    if [ -d "$CLONE_DIR" ]; then
        log_warning "Directory $CLONE_DIR already exists. Backing up..."
        mv "$CLONE_DIR" "${CLONE_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # Clone the repository
    log_info "Cloning repository: $REPO_PATH"
    gh repo clone "$REPO_PATH" "$CLONE_DIR"
    
    log_success "Repository cloned to: $CLONE_DIR"
    
    # Export for use in subsequent scripts
    export STACK_DIR=$CLONE_DIR
    export CLONE_DIR=$CLONE_DIR
}

# System validation
validate_system() {
    log_info "Validating system configuration..."
    
    # Check Docker
    if docker run --rm hello-world &> /dev/null; then
        log_success "Docker is working correctly"
    else
        log_error "Docker test failed"
        exit 1
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG /opt | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 20 ]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available (recommended: 20GB+)"
    else
        log_success "Disk space adequate: ${AVAILABLE_SPACE}GB available"
    fi
    
    # Check memory
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 4 ]; then
        log_warning "Low memory: ${TOTAL_MEM}GB available (recommended: 4GB+)"
    else
        log_success "Memory adequate: ${TOTAL_MEM}GB available"
    fi
}

# Main installation flow
main() {
    clear
    
    # Pre-flight checks
    check_root
    detect_os
    
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}   Stack Masters Setup Script v${VERSION}${NC}"
    echo -e "${BLUE}   $OS_NAME${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
    log_info "Starting Stack Masters setup..."
    log_info "Detected OS: $OS_NAME"
    log_info "OS Type: $OS_TYPE"
    echo ""
    
    # Display what this script will do
    echo -e "${YELLOW}This script will:${NC}"
    echo -e "${YELLOW}  1. Check your system for required packages${NC}"
    echo -e "${YELLOW}  2. Install missing packages (with your permission)${NC}"
    if [ "$OS_TYPE" = "server" ]; then
        echo -e "${YELLOW}  3. Configure firewall (Server OS detected)${NC}"
    else
        echo -e "${YELLOW}  3. Skip firewall configuration (Desktop OS detected)${NC}"
    fi
    echo -e "${YELLOW}  4. Authenticate with GitHub${NC}"
    echo -e "${YELLOW}  5. Clone the Stack Masters repository${NC}"
    echo ""
    echo -e "${BLUE}Press any key to continue...${NC}"
    read -n 1 -s
    echo ""
    
    # Check system packages
    check_system_packages
    
    # Confirm installation with user
    if ! confirm_installation; then
        log_info "Setup cancelled"
        exit 0
    fi
    
    # System preparation
    update_system
    install_core_deps
    
    # Install missing components
    if [ "$GIT_INSTALLED" = false ]; then
        install_git
    fi
    
    if [ "$GH_INSTALLED" = false ]; then
        install_github_cli
    fi
    
    if [ "$DOCKER_INSTALLED" = false ]; then
        install_docker
    fi
    
    # Configure system
    configure_firewall
    
    # GitHub authentication
    github_auth
    
    # Clone the repository
    clone_repository
    
    # Setup and start provisioning wizard
    setup_provisioning_wizard
    start_provisioning_wizard
    
    # Validate installation
    validate_system
    
    echo ""
    echo "=============================================="
    log_success "Stack Masters initial setup completed!"
    echo "=============================================="
    echo ""
    log_info "The Stack Masters Provisioning Wizard is now running"
    log_info "Use the web interface to complete your stack deployment"
    echo ""
    log_info "Next steps:"
    echo "  1. Open the provisioning wizard in your browser"
    echo "  2. Select your stack configuration"
    echo "  3. Follow the guided setup process"
    echo ""
    log_info "The wizard will handle:"
    echo "  - Environment configuration" 
    echo "  - Service deployment"
    echo "  - SSL certificate setup"
    echo ""
    log_info "Repository cloned to: $CLONE_DIR"
    echo ""
}

# Run main function
main "$@"