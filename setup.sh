#!/bin/bash
# Stack Masters Setup Script - Universal Linux Server Provisioning
# This script prepares a fresh Linux VPS/server for Stack Masters deployment
# Works with: Hostinger, DigitalOcean, Vultr, AWS EC2, Linode, or any Linux VPS
# Supports: Ubuntu 20.04+, Debian 10+, RHEL 8+, CentOS 8+, AlmaLinux 8+

set -euo pipefail

# Script version
VERSION="1.0.0"

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
    
    log_success "Detected: $OS_NAME"
    log_success "Package manager: $PKG_MANAGER"
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
    log_info "Configuring firewall rules..."
    
    # Open all required ports for both production and local development
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
    
    log_info "Note: Opening all service ports to support both domain-based (reverse proxy) and direct access configurations"
    
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
    log_info "A browser window will open for authentication"
    log_info "If you're on a remote server, you'll see a code to enter at: https://github.com/login/device"
    echo ""
    
    # Attempt browser-based auth first, fall back to device code
    if ! gh auth login --web 2>/dev/null; then
        log_info "Browser authentication not available, using device code flow..."
        gh auth login
    fi
    
    if gh auth status &> /dev/null; then
        log_success "GitHub authentication successful"
    else
        log_error "GitHub authentication failed"
        exit 1
    fi
}

# Clone appropriate repository
clone_repository() {
    log_info "Repository Setup"
    echo ""
    echo "Please provide the GitHub repository URL to clone."
    echo "Examples:"
    echo "  - https://github.com/Tech-to-Thrive/stack-masters"
    echo "  - https://github.com/Tech-to-Thrive/stack-masters-pro"
    echo "  - https://github.com/Tech-to-Thrive/agent-hosting"
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
    echo "=============================================="
    echo "   Stack Masters Setup Script v${VERSION}"
    echo "   Universal VPS/Server Provisioning"
    echo "=============================================="
    echo ""
    log_info "Compatible with: Hostinger, DigitalOcean, Vultr, AWS, Linode, etc."
    echo ""
    
    # Pre-flight checks
    check_root
    detect_os
    
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
    
    echo ""
    echo "=============================================="
    log_success "Stack deployment setup completed successfully!"
    echo "=============================================="
    echo ""
    log_info "Repository location: ${STACK_DIR}"
    log_info "Next steps:"
    echo "  1. cd ${STACK_DIR}"
    echo "  2. ./setup-environment.sh (if available)"
    echo "  3. ./install.sh"
    echo ""
}

# Run main function
main "$@"