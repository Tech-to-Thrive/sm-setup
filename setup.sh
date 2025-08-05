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

# Initialize logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGS_DIR"
# Create timestamped log filename
LOG_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOGFILE="$LOGS_DIR/stack-masters-setup-$LOG_TIMESTAMP.log"

# Write log header
echo "================================================" >> "$LOGFILE"
echo "Stack Masters Setup Script - Started at $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
echo "================================================" >> "$LOGFILE"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOGFILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOGFILE"
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
    # Only configure ports actually used by Stack Masters
    # Removed ports 80 and 443 - not needed by Stack Masters
    PORTS=(
        "58217:tcp"   # Provisioning wizard
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

# GitHub authentication is now handled by the web wizard
# This function is kept for reference but no longer used
# github_auth() {
#     # Moved to web wizard
# }

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
    # PROJECT_ROOT will be set after cloning via web wizard
    export PORT="58217"
    export NODE_ENV="production"
    export HOST=$([ "$OS_TYPE" = "desktop" ] && echo "localhost" || echo "0.0.0.0")
    
    log_info "Starting provisioning wizard on port 58217..."
    
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
    echo -e "  ${BLUE}http://localhost:58217${NC}"
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
            echo -e "  ${BLUE}http://${ip}:58217${NC}"
        done
    fi
    echo ""
    echo -e "${YELLOW}The wizard will guide you through:${NC}"
    echo "  - Selecting your Stack Masters repository"
    echo "  - Configuring your environment"
    echo "  - Deploying your services"
    echo ""
}

# Repository cloning is now handled by the web wizard
# This function is kept for reference but no longer used
# clone_repository() {
#     # Moved to web wizard - handled via /api/github/clone endpoint
# }

# Comprehensive system validation
validate_system_requirements() {
    log_info "Running comprehensive system validation..."
    
    local validation_errors=0
    
    # Check disk space (minimum 10GB - sufficient for Docker images and data)
    log_info "Checking disk space..."
    AVAILABLE_SPACE=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    TOTAL_SPACE=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//')
    
    if [ -z "$AVAILABLE_SPACE" ] || [ "$AVAILABLE_SPACE" -lt 10 ]; then
        log_error "Insufficient disk space: ${AVAILABLE_SPACE:-0}GB available, 10GB required"
        ((validation_errors++))
    elif [ "$AVAILABLE_SPACE" -lt 15 ]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available. Consider having at least 15GB for optimal performance."
        log_success "Disk space: ${AVAILABLE_SPACE}GB available (minimum requirement met) ✓"
    else
        log_success "Disk space: ${AVAILABLE_SPACE}GB available of ${TOTAL_SPACE}GB total ✓"
    fi
    
    # Check memory (minimum 4GB)
    log_info "Checking system memory..."
    # Get memory in MB first for accuracy, then convert to GB
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    AVAILABLE_MEM_MB=$(free -m | awk '/^Mem:/{print $7}')
    TOTAL_MEM=$(echo "scale=1; $TOTAL_MEM_MB / 1024" | bc 2>/dev/null || echo "$((TOTAL_MEM_MB / 1024))")
    AVAILABLE_MEM=$(echo "scale=1; $AVAILABLE_MEM_MB / 1024" | bc 2>/dev/null || echo "$((AVAILABLE_MEM_MB / 1024))")
    
    if [ "$TOTAL_MEM_MB" -lt 4096 ]; then
        log_error "Insufficient memory: ${TOTAL_MEM}GB total, 4GB required"
        ((validation_errors++))
    else
        log_success "Memory: ${TOTAL_MEM}GB total, ${AVAILABLE_MEM}GB available ✓"
    fi
    
    # Check CPU cores (recommend at least 2)
    log_info "Checking CPU cores..."
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "Only $CPU_CORES CPU core(s) detected. Performance may be limited."
    else
        log_success "CPU cores: $CPU_CORES ✓"
    fi
    
    # Validate Docker daemon
    log_info "Validating Docker installation..."
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        ((validation_errors++))
    else
        # Check if Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            log_warning "Docker daemon is not running. Attempting to start..."
            if command -v systemctl &> /dev/null; then
                systemctl start docker 2>/dev/null || true
                systemctl enable docker 2>/dev/null || true
            elif command -v service &> /dev/null; then
                service docker start 2>/dev/null || true
            fi
            
            # Wait and retry
            sleep 3
            if ! docker info >/dev/null 2>&1; then
                log_error "Failed to start Docker daemon"
                ((validation_errors++))
            else
                log_success "Docker daemon started successfully ✓"
            fi
        else
            log_success "Docker daemon is running ✓"
        fi
        
        # Test Docker functionality
        if docker info >/dev/null 2>&1; then
            if ! docker run --rm hello-world >/dev/null 2>&1; then
                log_error "Docker test failed. Please check Docker installation."
                ((validation_errors++))
            else
                log_success "Docker functionality verified ✓"
            fi
        fi
    fi
    
    # Check Docker Compose
    log_info "Checking Docker Compose..."
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null)
        log_success "Docker Compose v2 available: $COMPOSE_VERSION ✓"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}' | sed 's/,$//')
        log_success "Docker Compose v1 available: $COMPOSE_VERSION ✓"
    else
        log_error "Docker Compose not found"
        ((validation_errors++))
    fi
    
    # Check critical ports availability
    log_info "Checking port availability..."
    check_port_availability() {
        local port=$1
        local service=$2
        
        if command -v lsof &> /dev/null; then
            if lsof -i:$port >/dev/null 2>&1; then
                log_error "Port $port is already in use (required for $service)"
                return 1
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                log_error "Port $port is already in use (required for $service)"
                return 1
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":$port "; then
                log_error "Port $port is already in use (required for $service)"
                return 1
            fi
        fi
        return 0
    }
    
    # Check wizard port
    if ! check_port_availability 58217 "Provisioning Wizard"; then
        ((validation_errors++))
    else
        log_success "Port 58217 available for wizard ✓"
    fi
    
    # Check other ports used by Stack Masters services (warnings only)
    # Removed ports 80 and 443 - not needed by Stack Masters
    local WARNING_PORTS=(3000 3001 5678 9090)
    for port in "${WARNING_PORTS[@]}"; do
        if ! check_port_availability $port "Stack Services" 2>/dev/null; then
            log_warning "Port $port is in use. This may cause conflicts during deployment."
        fi
    done
    
    # Test internet connectivity
    log_info "Checking internet connectivity..."
    if ! curl -s --head --connect-timeout 5 https://github.com >/dev/null; then
        log_error "No internet connectivity detected. Please check your network connection."
        ((validation_errors++))
    else
        log_success "Internet connectivity verified ✓"
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        ((validation_errors++))
    else
        log_success "Running with root privileges ✓"
    fi
    
    # Summary
    echo ""
    if [ $validation_errors -eq 0 ]; then
        log_success "All system validation checks passed! ✓"
        return 0
    else
        log_error "System validation failed with $validation_errors error(s)"
        log_info "Please resolve the issues above and try again"
        return 1
    fi
}

# Setup provisioning wizard
setup_provisioning_wizard() {
    log_info "Setting up Stack Masters Provisioning Wizard..."
    
    # Create wizard directory in run folder
    RUN_DIR="$SCRIPT_DIR/run"
    mkdir -p "$RUN_DIR"
    
    WIZARD_DIR="$RUN_DIR/provisioning-wizard"
    
    # Don't try to delete existing directory - just update it in place
    if [ -d "$WIZARD_DIR" ]; then
        log_info "Wizard directory already exists. Updating files in place..."
        
        # Clean up any PID files from previous runs
        rm -f "$WIZARD_DIR/wizard.pid" "$WIZARD_DIR/backend/wizard.pid" 2>/dev/null
        
        # Clean up node_modules to ensure fresh install
        if [ -d "$WIZARD_DIR/backend/node_modules" ]; then
            log_info "Cleaning up old node_modules..."
            rm -rf "$WIZARD_DIR/backend/node_modules"
        fi
        
        # Clean up package-lock.json to avoid conflicts
        rm -f "$WIZARD_DIR/backend/package-lock.json" 2>/dev/null
    else
        # Create new directory
        log_info "Creating wizard directory..."
        mkdir -p "$WIZARD_DIR"
    fi
    
    # Copy provisioning web app
    SOURCE_DIR="$SCRIPT_DIR/apps/provisioning-web"
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Provisioning web app not found at: $SOURCE_DIR"
        exit 1
    fi
    
    # Use rsync if available for better handling of existing files
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --delete "$SOURCE_DIR/" "$WIZARD_DIR/" >/dev/null 2>&1
    else
        cp -r "$SOURCE_DIR"/* "$WIZARD_DIR/"
    fi
    
    log_success "Provisioning wizard files updated successfully"
}

# Stop any existing wizard processes (aggressive cleanup like PowerShell)
stop_existing_wizard() {
    log_info "Checking for existing wizard processes..."
    
    local cleanup_performed=false
    
    # Method 1: Kill ALL processes on port 58217 (our unique wizard port)
    log_info "Checking port 58217..."
    if command -v lsof >/dev/null 2>&1; then
        local pids=$(lsof -ti:58217 2>/dev/null)
        if [ -n "$pids" ]; then
            log_warning "Found $(echo "$pids" | wc -w) process(es) using port 58217. Force stopping all..."
            for pid in $pids; do
                log_info "Force stopping process on port 58217 (PID: $pid)..."
                kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                cleanup_performed=true
            done
            sleep 3
        fi
    elif command -v ss >/dev/null 2>&1; then
        # Fallback to ss command
        local pids=$(ss -tlnp 2>/dev/null | grep ":58217" | grep -oP 'pid=\K\d+' || true)
        if [ -n "$pids" ]; then
            log_warning "Found process using port 58217. Force stopping..."
            for pid in $pids; do
                log_info "Force stopping process on port 58217 (PID: $pid)..."
                kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                cleanup_performed=true
            done
            sleep 3
        fi
    elif command -v netstat >/dev/null 2>&1; then
        # Last resort - netstat
        local pids=$(netstat -tlnp 2>/dev/null | grep ":58217" | awk '{print $7}' | cut -d'/' -f1)
        if [ -n "$pids" ]; then
            log_warning "Found process using port 58217. Force stopping..."
            for pid in $pids; do
                if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                    log_info "Force stopping process on port 58217 (PID: $pid)..."
                    kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                    cleanup_performed=true
                fi
            done
            sleep 3
        fi
    fi
    
    # Method 2: Check for PID files
    local pid_files=(
        "$SCRIPT_DIR/run/provisioning-wizard/wizard.pid"
        "$SCRIPT_DIR/run/provisioning-wizard/backend/wizard.pid"
    )
    
    for pid_file in "${pid_files[@]}"; do
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file" 2>/dev/null)
            if [ -n "$pid" ]; then
                log_info "Found PID file. Force stopping process (PID: $pid)..."
                kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                cleanup_performed=true
            fi
            rm -f "$pid_file"
        fi
    done
    
    # Method 3: Kill ALL node processes that might be ours
    log_info "Checking for Node.js processes..."
    local node_pids=""
    
    # Try multiple methods to find node processes
    if command -v pgrep >/dev/null 2>&1; then
        node_pids=$(pgrep -f "node.*provisioning-wizard" 2>/dev/null || true)
        node_pids="$node_pids $(pgrep -f "node.*server-integrated.js" 2>/dev/null || true)"
    fi
    
    if command -v ps >/dev/null 2>&1; then
        # Also check with ps for any missed processes
        local ps_pids=$(ps aux | grep -E "node.*(provisioning-wizard|server-integrated)" | grep -v grep | awk '{print $2}' || true)
        node_pids="$node_pids $ps_pids"
    fi
    
    # Remove duplicates and empty entries
    node_pids=$(echo "$node_pids" | tr ' ' '\n' | sort -u | grep -v '^$' || true)
    
    if [ -n "$node_pids" ]; then
        local count=$(echo "$node_pids" | wc -w)
        log_warning "Found $count Node.js process(es). Checking which are wizard processes..."
        
        for pid in $node_pids; do
            if [ -n "$pid" ]; then
                # Check if process still exists
                if kill -0 "$pid" 2>/dev/null; then
                    log_info "Force stopping wizard Node.js process (PID: $pid)..."
                    kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                    cleanup_performed=true
                fi
            fi
        done
    fi
    
    # Method 4: Clean up any processes that have our wizard directory open
    if command -v lsof >/dev/null 2>&1; then
        local wizard_dir="$SCRIPT_DIR/run/provisioning-wizard"
        if [ -d "$wizard_dir" ]; then
            log_info "Checking for processes locking wizard directory..."
            local dir_pids=$(lsof +D "$wizard_dir" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
            if [ -n "$dir_pids" ]; then
                for pid in $dir_pids; do
                    # Get process name
                    local pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                    if [[ "$pname" == *"node"* ]]; then
                        log_info "Force stopping process with wizard directory open: $pname (PID: $pid)..."
                        kill -KILL "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
                        cleanup_performed=true
                    fi
                done
            fi
        fi
    fi
    
    if [ "$cleanup_performed" = true ]; then
        log_success "Aggressive cleanup completed. Waiting for processes to fully terminate..."
        sleep 5  # Give more time for processes to die
        
        # Double-check port is free
        local port_still_used=false
        if command -v lsof >/dev/null 2>&1; then
            if lsof -ti:58217 >/dev/null 2>&1; then
                port_still_used=true
            fi
        elif command -v ss >/dev/null 2>&1; then
            if ss -tlnp 2>/dev/null | grep -q ":58217"; then
                port_still_used=true
            fi
        fi
        
        if [ "$port_still_used" = true ]; then
            log_warning "Port 58217 is STILL in use. Attempting final cleanup..."
            # Last resort - kill anything on port 58217
            if command -v fuser >/dev/null 2>&1; then
                fuser -k 58217/tcp 2>/dev/null || true
            fi
            sleep 2
        else
            log_success "Port 58217 is now available ✓"
        fi
    else
        log_success "No existing wizard processes found ✓"
    fi
    
    # Final cleanup - remove any stale PID files
    rm -f "$SCRIPT_DIR/run/provisioning-wizard/wizard.pid" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/run/provisioning-wizard/backend/wizard.pid" 2>/dev/null || true
}

# Run wizard-specific diagnostics
test_wizard_diagnostics() {
    log_info "Running wizard pre-flight diagnostics..."
    
    local issues=()
    local warnings=()
    
    # Check Node.js
    if ! command -v node >/dev/null 2>&1; then
        issues+=("Node.js is not installed or not in PATH")
    else
        local node_version=$(node --version 2>&1)
        log_success "Node.js installed: $node_version"
        # Check if version is at least v16
        if [[ "$node_version" =~ v([0-9]+)\. ]]; then
            local major_version="${BASH_REMATCH[1]}"
            if [ "$major_version" -lt 16 ]; then
                warnings+=("Node.js version $node_version is below recommended v16+")
            fi
        fi
    fi
    
    # Check npm
    if ! command -v npm >/dev/null 2>&1; then
        issues+=("npm is not installed or not in PATH")
    else
        local npm_version=$(npm --version 2>&1)
        log_success "npm installed: $npm_version"
    fi
    
    # Check port 58217 with detailed information
    log_info "Checking port 58217 availability..."
    local port_in_use=false
    local process_info=""
    
    if command -v lsof >/dev/null 2>&1; then
        local port_check=$(lsof -i:58217 2>/dev/null)
        if [ -n "$port_check" ]; then
            port_in_use=true
            local pid=$(echo "$port_check" | awk 'NR==2 {print $2}')
            local pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            process_info="Process using port: $pname (PID: $pid)"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":58217"; then
            port_in_use=true
            process_info="Port 58217 is in use (use 'ss -tlnp | grep :58217' to see details)"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":58217"; then
            port_in_use=true
            process_info="Port 58217 is in use (use 'netstat -tlnp | grep :58217' to see details)"
        fi
    fi
    
    if [ "$port_in_use" = true ]; then
        issues+=("Port 58217 is already in use!")
        if [ -n "$process_info" ]; then
            issues+=("  $process_info")
        fi
        log_info "Please stop the process using port 58217 or choose a different port"
    else
        log_success "Port 58217 is available"
    fi
    
    # Check firewall rules (for server environments)
    if [ "$OS_TYPE" = "server" ]; then
        if command -v ufw >/dev/null 2>&1; then
            if ufw status 2>/dev/null | grep -q "58217"; then
                log_success "Firewall rule found for port 58217"
            else
                warnings+=("No firewall rule found for port 58217 on server OS")
            fi
        elif command -v firewall-cmd >/dev/null 2>&1; then
            if firewall-cmd --list-ports 2>/dev/null | grep -q "58217"; then
                log_success "Firewall rule found for port 58217"
            else
                warnings+=("No firewall rule found for port 58217 on server OS")
            fi
        fi
    fi
    
    # Check available memory
    local available_mem_mb=$(free -m | awk '/^Mem:/{print $7}')
    local available_mem_gb=$(echo "scale=1; $available_mem_mb / 1024" | bc 2>/dev/null || echo "$((available_mem_mb / 1024))")
    if [ "$available_mem_mb" -lt 1024 ]; then
        warnings+=("Low available memory: ${available_mem_gb}GB (recommend 1GB+)")
    fi
    
    # Check disk space in temp directory
    local temp_disk=$(df -BG /tmp 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ -n "$temp_disk" ] && [ "$temp_disk" -lt 2 ]; then
        issues+=("Low disk space on /tmp: ${temp_disk}GB (need 2GB+)")
    fi
    
    # Report results
    if [ ${#issues[@]} -gt 0 ]; then
        log_error "Critical issues found:"
        for issue in "${issues[@]}"; do
            echo -e "  ${RED}• $issue${NC}"
        done
    fi
    
    if [ ${#warnings[@]} -gt 0 ]; then
        log_warning "Potential issues found:"
        for warning in "${warnings[@]}"; do
            echo -e "  ${YELLOW}• $warning${NC}"
        done
    fi
    
    if [ ${#issues[@]} -eq 0 ] && [ ${#warnings[@]} -eq 0 ]; then
        log_success "No issues detected"
    fi
    
    # Return status
    if [ ${#issues[@]} -gt 0 ]; then
        return 1  # Has critical issues
    else
        return 0  # OK to proceed (warnings are acceptable)
    fi
}

# Start provisioning wizard
start_provisioning_wizard() {
    log_info "Starting Stack Masters Provisioning Wizard..."
    
    WIZARD_DIR="$SCRIPT_DIR/run/provisioning-wizard"
    BACKEND_DIR="$WIZARD_DIR/backend"
    
    if [ ! -d "$BACKEND_DIR" ]; then
        log_error "Backend directory not found: $BACKEND_DIR"
        exit 1
    fi
    
    # Check if Node.js is available
    if ! command -v node >/dev/null 2>&1; then
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
        
        if ! command -v node >/dev/null 2>&1; then
            log_error "Failed to install Node.js"
            exit 1
        fi
        
        log_success "Node.js installed successfully"
    fi
    
    # Validate Node.js installation
    log_info "Validating Node.js installation..."
    node_version=$(node --version 2>&1)
    log_info "Node.js version: $node_version"
    
    # Check if npm is available
    if ! command -v npm >/dev/null 2>&1; then
        log_error "npm is not available. Please ensure Node.js installation includes npm."
        exit 1
    fi
    
    # Validate npm
    npm_version=$(npm --version 2>&1)
    log_info "npm version: $npm_version"
    
    # Install dependencies
    log_info "Installing dependencies..."
    cd "$BACKEND_DIR"
    
    # Simple direct approach - just run npm install
    log_info "Running npm install (this may take a minute)..."
    
    npm_install_success=false
    npm_install_output=""
    
    # Method 1: Direct invocation with output capture
    if npm_install_output=$(npm install --production 2>&1); then
        npm_install_success=true
        log_success "npm install completed successfully"
    else
        log_warning "Direct npm invocation failed, trying alternative method..."
        
        # Method 2: Try with different flags
        if npm_install_output=$(npm install --production --no-audit --no-fund 2>&1); then
            npm_install_success=true
            log_success "npm install completed successfully (alternative method)"
        else
            # Method 3: Try cleaning cache first
            log_warning "Trying with cache clean..."
            npm cache clean --force >/dev/null 2>&1 || true
            
            if npm_install_output=$(npm install --production 2>&1); then
                npm_install_success=true
                log_success "npm install completed successfully (after cache clean)"
            fi
        fi
    fi
    
    # Check if npm install succeeded
    if [ "$npm_install_success" = false ]; then
        log_error "Automated npm install failed"
        log_error "npm output: $npm_install_output"
        echo ""
        echo -e "${RED}Manual installation required:${NC}"
        echo -e "${YELLOW}Please run the following commands manually:${NC}"
        echo -e "  ${BLUE}cd \"$BACKEND_DIR\"${NC}"
        echo -e "  ${BLUE}npm install --production${NC}"
        echo ""
        echo -e "${YELLOW}Press any key after manual installation completes...${NC}"
        read -n 1 -s
        echo ""
        
        # Verify node_modules exists
        if [ ! -d "$BACKEND_DIR/node_modules" ]; then
            log_error "node_modules directory not found. Please ensure npm install completed successfully."
            exit 1
        fi
        log_success "Continuing with manual npm install"
    fi
    
    log_success "Dependencies installed successfully"
    
    # Determine host binding based on environment
    if [ "$OS_TYPE" = "server" ]; then
        HOST_BINDING="0.0.0.0"
    else
        HOST_BINDING="localhost"
    fi
    
    # Set environment variables and start server in background
    export HOST="$HOST_BINDING"
    export PORT="58217"
    export NODE_ENV="production"
    
    log_info "Starting provisioning wizard on port 58217..."
    
    # Start Node.js server in background with timestamped log
    WIZARD_LOG_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    nohup node server-integrated.js > "$LOGS_DIR/wizard-$WIZARD_LOG_TIMESTAMP.log" 2>&1 &
    WIZARD_PID=$!
    
    # Save PID for potential cleanup
    echo "$WIZARD_PID" > "$WIZARD_DIR/wizard.pid"
    log_info "Provisioning wizard started with PID: $WIZARD_PID"
    
    # Monitor startup for errors (first 10 seconds)
    log_info "Monitoring startup for errors..."
    startup_timeout=10
    startup_start=$(date +%s)
    process_started=false
    has_errors=false
    
    while [ $(($(date +%s) - startup_start)) -lt $startup_timeout ]; do
        # Check if process is still running
        if ! kill -0 "$WIZARD_PID" 2>/dev/null; then
            log_error "Node.js process exited unexpectedly"
            
            # Try to read output from log file for error details
            if [ -f "$LOGS_DIR/wizard-$WIZARD_LOG_TIMESTAMP.log" ]; then
                error_output=$(tail -n 20 "$LOGS_DIR/wizard-$WIZARD_LOG_TIMESTAMP.log" 2>/dev/null || true)
                if [ -n "$error_output" ]; then
                    log_error "Process error output:"
                    echo "$error_output"
                fi
            fi
            
            has_errors=true
            break
        fi
        
        # Check if server is responding - try multiple endpoints
        # Try root endpoint (health endpoint requires auth)
        if curl -s -m 2 "http://$HOST_BINDING:58217/" >/dev/null 2>&1; then
            process_started=true
            break
        fi
        
        # Also check the specific HTTP response codes
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "http://$HOST_BINDING:58217/" 2>/dev/null || echo "000")
        # 401 Unauthorized or 403 Forbidden means server is running but requires auth - that's fine!
        if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
            process_started=true
            log_success "Server is responding (authentication required)"
            break
        fi
        
        # Also try the health endpoint
        health_code=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "http://$HOST_BINDING:58217/api/health" 2>/dev/null || echo "000")
        if [ "$health_code" = "200" ] || [ "$health_code" = "401" ] || [ "$health_code" = "403" ]; then
            process_started=true
            log_success "Server is responding (health endpoint accessible)"
            break
        fi
        
        sleep 0.5
    done
    
    # Determine startup result
    if [ "$has_errors" = true ]; then
        log_error "❌ FAILED TO START PROVISIONING WIZARD"
        log_error "Node.js process failed to start properly"
        echo ""
        echo -e "${RED}Troubleshooting steps:${NC}"
        echo -e "  1. Check the log files in: ${YELLOW}$LOGS_DIR${NC}"
        echo -e "  2. Verify Node.js and npm are working: ${YELLOW}node --version && npm --version${NC}"
        echo -e "  3. Check if port 58217 is available: ${YELLOW}lsof -i:58217${NC}"
        echo -e "  4. Try running the wizard manually:"
        echo -e "     ${BLUE}cd \"$BACKEND_DIR\"${NC}"
        echo -e "     ${BLUE}npm install${NC}"
        echo -e "     ${BLUE}HOST=$HOST_BINDING PORT=58217 NODE_ENV=production node server-integrated.js${NC}"
        echo ""
        echo -e "${RED}Setup failed - wizard is not running${NC}"
        exit 1
    elif [ "$process_started" = true ]; then
        log_success "Provisioning wizard started successfully!"
        # Silently proceed to show wizard info
        show_wizard_access_info "$HOST_BINDING"
    else
        # Process is running but not responding
        log_warning "Node.js process is running but server is not responding on port 58217"
        log_warning "This usually indicates a configuration or dependency issue"
        
        # Try to get some output from the log
        if [ -f "$LOGS_DIR/wizard-$WIZARD_LOG_TIMESTAMP.log" ]; then
            log_info "Recent log output:"
            tail -n 20 "$LOGS_DIR/wizard-$WIZARD_LOG_TIMESTAMP.log" 2>/dev/null || true
        fi
        
        # Kill the non-responsive process
        log_info "Terminating non-responsive process..."
        kill -TERM "$WIZARD_PID" 2>/dev/null || true
        sleep 2
        kill -KILL "$WIZARD_PID" 2>/dev/null || true
        
        log_error "Server failed to start - check logs for details"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Show wizard access information
show_wizard_access_info() {
    local host_binding="$1"
    
    # Try to extract token from wizard output log
    local token_info=""
    local wizard_log=$(ls -t "$LOGS_DIR"/wizard-*.log 2>/dev/null | head -1)
    
    if [ -n "$wizard_log" ] && [ -f "$wizard_log" ]; then
        # Extract token from log - try multiple patterns
        token_info=$(grep -oP 'Token:\s*\K[a-f0-9]{64}' "$wizard_log" 2>/dev/null || true)
        if [ -z "$token_info" ]; then
            # Try alternative pattern
            token_info=$(grep -oP 'token=\K[a-f0-9]{64}' "$wizard_log" 2>/dev/null || true)
        fi
    fi
    
    # Save wizard info silently
    local run_dir="$SCRIPT_DIR/run"
    local wizard_dir="$run_dir/provisioning-wizard"
    
    # Ensure directory exists
    mkdir -p "$wizard_dir"
    
    local wizard_info_file="$wizard_dir/wizard-info.txt"
    {
        echo "Wizard URL: http://localhost:58217/?token=$token_info"
        echo "Token: $token_info"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    } > "$wizard_info_file"
    
    # Clear output and show only essential info
    echo ""
    echo ""
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        NEXT STEP - OPEN YOUR BROWSER${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ -n "$token_info" ]; then
        echo "Open this URL in your browser:"
        echo ""
        echo -e "${YELLOW}  http://localhost:58217/?token=$token_info${NC}"
        echo ""
        echo -e "${RED}⚠️  This token expires in 30 minutes!${NC}"
        
        if [ "$host_binding" != "localhost" ]; then
            echo ""
            echo -e "${GRAY:-}Remote access (if needed):${NC}"
            # Show network interfaces for remote access
            if command -v ip >/dev/null 2>&1; then
                ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | while read -r ip; do
                    echo -e "${GRAY:-}  http://$ip:58217/?token=$token_info${NC}"
                done
            elif command -v hostname >/dev/null 2>&1; then
                # Try multiple methods to get IP
                local_ips=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
                if [ -z "$local_ips" ]; then
                    # Alternative method
                    local_ips=$(ip route get 1 2>/dev/null | awk '{print $7}' || true)
                fi
                if [ -n "$local_ips" ]; then
                    for ip in $local_ips; do
                        echo -e "${GRAY:-}  http://$ip:58217/?token=$token_info${NC}"
                    done
                else
                    echo -e "${GRAY:-}  http://YOUR-SERVER-IP:58217/?token=$token_info${NC}"
                fi
            else
                echo -e "${GRAY:-}  http://YOUR-SERVER-IP:58217/?token=$token_info${NC}"
            fi
        fi
    else
        echo "Open this URL in your browser:"
        echo ""
        echo -e "${YELLOW}  http://localhost:58217${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo ""
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
    log_info "Log file: $LOGFILE"
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
    
    # Run comprehensive validation before proceeding
    log_info "Performing system validation..."
    if ! validate_system_requirements; then
        log_error "System validation failed. Please fix the issues and try again."
        exit 1
    fi
    
    # Stop any existing wizard processes
    echo ""
    stop_existing_wizard
    
    # Run wizard-specific diagnostics
    echo ""
    if ! test_wizard_diagnostics; then
        log_error "Critical issues detected that will prevent the wizard from starting"
        log_info "Please resolve the issues above and try again"
        exit 1
    fi
    
    # Setup and start provisioning wizard
    echo ""
    log_info "All checks passed - setting up provisioning wizard..."
    setup_provisioning_wizard
    start_provisioning_wizard
    
    # Keep output minimal - show_wizard_access_info already shows the important info
    echo ""
}

# Run main function
main "$@"