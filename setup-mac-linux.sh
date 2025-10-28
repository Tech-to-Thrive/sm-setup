#!/bin/bash
# Stack Masters Setup Script - Universal Setup for macOS and Linux
# 
# USAGE: Always run without sudo: ./setup-mac-linux.sh
#        The script will auto-elevate on Linux if needed
#
# Default Install Locations:
#   macOS: /Users/Shared/stack-masters (shared, no sudo required)
#   Linux: /opt/stack-masters (system-wide, may require sudo)
#
# Supports: macOS, Ubuntu 20.04+, Debian 10+, RHEL 8+, CentOS 8+, AlmaLinux 8+

set -euo pipefail

# Script version
VERSION="1.3.0"

# Parse command line arguments
SKIP_AUTH=false
REPO_URL=""
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-auth)
            SKIP_AUTH=true
            shift
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --yes|-y)
            AUTO_CONFIRM=true
            shift
            ;;
        --help)
            echo "Stack Masters Setup Script v$VERSION"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "IMPORTANT: Always run WITHOUT sudo. The script will auto-elevate on Linux."
            echo ""
            echo "Options:"
            echo "  --skip-auth       Skip GitHub authentication (for testing)"
            echo "  --repo-url URL    GitHub repository URL to clone"
            echo "  --yes, -y         Auto-confirm installation (skip confirmation prompt)"
            echo "  --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Interactive setup"
            echo "  $0 --repo-url https://github.com/org/repo"
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Initialize logging and state tracking
# Always use a safe location for logs that won't be deleted during setup
STATE_DIR="${HOME}/.stack-masters"
LOG_DIR="${STATE_DIR}/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || {
    STATE_DIR="/tmp/stack-masters-state"
    LOG_DIR="/tmp/stack-masters-logs"
    mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
}
LOG_FILE="$LOG_DIR/stack-masters-setup-$(date +%Y%m%d-%H%M%S).log"
STATE_FILE="$STATE_DIR/setup-state.json"

# State management functions (using simple key=value format, no jq dependency)
save_state() {
    local key="$1"
    local value="$2"
    # Ensure state directory exists
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    
    # Create or update state file
    if [ -f "$STATE_FILE" ]; then
        # Remove existing key if present
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    # Append new key=value
    echo "${key}=${value}" >> "$STATE_FILE"
}

get_state() {
    local key="$1"
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2-
    fi
}

clear_state() {
    rm -f "$STATE_FILE" 2>/dev/null
}

# Log functions with safe writing
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null
    fi
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

# Check if core dependencies are already installed
check_core_deps() {
    local missing_deps=false
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        missing_deps=true
        return 1
    fi
    
    # Check for wget
    if ! command -v wget &> /dev/null; then
        missing_deps=true
        return 1
    fi
    
    # Check for ca-certificates (different check per OS)
    if [[ "$OS" == "macos" ]]; then
        # macOS has ca-certificates built-in, check for gnupg instead
        if ! command -v gpg &> /dev/null; then
            missing_deps=true
            return 1
        fi
    else
        # Linux - check for gnupg/gpg
        if ! command -v gpg &> /dev/null && ! command -v gpg2 &> /dev/null; then
            missing_deps=true
            return 1
        fi
    fi
    
    return 0
}

# Check if all required software is already installed
check_all_requirements() {
    local all_installed=true
    
    # Check Git
    if ! command -v git &> /dev/null; then
        all_installed=false
    fi
    
    # Check GitHub CLI
    if ! command -v gh &> /dev/null; then
        all_installed=false
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        all_installed=false
    fi
    
    # Check core dependencies
    if ! check_core_deps; then
        all_installed=false
    fi
    
    if [ "$all_installed" = true ]; then
        return 0
    else
        return 1
    fi
}

# Install core dependencies
install_core_deps() {
    log_info "Installing core dependencies..."
    
    # Build list of packages we actually need to install
    CORE_PACKAGES=""
    
    # Check what's missing and add to install list
    # Skip curl on macOS as it's built-in and brew install curl causes issues
    if [[ "$OS" != "macos" ]] && ! command -v curl &> /dev/null; then
        CORE_PACKAGES="$CORE_PACKAGES curl"
    fi
    
    if ! command -v wget &> /dev/null; then
        CORE_PACKAGES="$CORE_PACKAGES wget"
    fi
    
    # Always include ca-certificates as it's hard to check consistently
    CORE_PACKAGES="$CORE_PACKAGES ca-certificates"
    
    # Distribution-specific adjustments
    case $PKG_MANAGER in
        brew)
            # macOS with Homebrew - minimal essentials only (skip curl as it's built-in)
            CORE_PACKAGES="wget ca-certificates"
            # Add gnupg if not already installed
            command -v gpg &> /dev/null || CORE_PACKAGES="$CORE_PACKAGES gnupg"
            ;;
        apt)
            # Ubuntu/Debian - universally available packages
            CORE_PACKAGES="$CORE_PACKAGES gnupg"
            # Only add apt-transport-https if not on modern systems (it's built-in on newer versions)
            if ! dpkg -l apt-transport-https &> /dev/null; then
                CORE_PACKAGES="$CORE_PACKAGES apt-transport-https"
            fi
            # Add lsb-release only if not present
            command -v lsb_release &> /dev/null || CORE_PACKAGES="$CORE_PACKAGES lsb-release"
            ;;
        yum|dnf)
            # CentOS/Red Hat/Rocky/AlmaLinux - minimal packages
            CORE_PACKAGES="$CORE_PACKAGES gnupg2"
            # which is more universal than lsb-release on RHEL-based systems
            command -v which &> /dev/null || CORE_PACKAGES="$CORE_PACKAGES which"
            ;;
        pacman)
            # Arch Linux - minimal essentials
            CORE_PACKAGES="$CORE_PACKAGES gnupg"
            # Only add make/gcc if needed for building
            command -v make &> /dev/null || CORE_PACKAGES="$CORE_PACKAGES make"
            ;;
        zypper)
            # SUSE/openSUSE - minimal packages
            CORE_PACKAGES="$CORE_PACKAGES gpg2"
            # Add which if not present
            command -v which &> /dev/null || CORE_PACKAGES="$CORE_PACKAGES which"
            ;;
    esac
    
    if [ -n "$(echo $CORE_PACKAGES | tr -d ' ')" ]; then
        log_info "Installing packages: $CORE_PACKAGES"
        $PKG_INSTALL $CORE_PACKAGES
    else
        log_info "All core packages already installed"
    fi
    
    # Validate critical network utilities are available
    validate_network_utilities
    
    log_success "Core dependencies installed and validated"
}

# Validate network utilities installation
validate_network_utilities() {
    local missing_tools=()
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    # Check for netcat (various possible commands)
    if ! command -v nc &> /dev/null && ! command -v netcat &> /dev/null && ! command -v ncat &> /dev/null; then
        missing_tools+=("netcat")
    fi
    
    # Check for timeout (part of coreutils)
    if ! command -v timeout &> /dev/null; then
        missing_tools+=("timeout")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "Some network utilities are not available: ${missing_tools[*]}"
        log_info "Scripts will use fallback methods for port checking"
        log_info "For optimal functionality, ensure these tools are installed:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                netcat)
                    case $PKG_MANAGER in
                        apt) echo "  sudo apt-get install netcat-openbsd" ;;
                        yum|dnf) echo "  sudo $PKG_MANAGER install nc" ;;
                        zypper) echo "  sudo zypper install netcat-openbsd" ;;
                        brew) echo "  brew install netcat" ;;
                        pacman) echo "  sudo pacman -S gnu-netcat" ;;
                    esac
                    ;;
                curl)
                    echo "  sudo $PKG_MANAGER install curl"
                    ;;
                timeout)
                    echo "  sudo $PKG_MANAGER install coreutils"
                    ;;
            esac
        done
    else
        log_success "All network utilities are available"
    fi
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
    
    # Detect remote environment (SSH or no display)
    if [[ -n "${SSH_CONNECTION:-}" ]] || [[ -z "${DISPLAY:-}" ]]; then
        log_info "Remote environment detected - using device code authentication"
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

# Normalize GitHub URL to standard format
normalize_github_url() {
    local url="$1"
    
    # Return empty if no URL provided
    if [ -z "$url" ]; then
        echo ""
        return
    fi
    
    # Trim whitespace (works on both macOS and Linux)
    url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Remove trailing slashes
    url="${url%/}"
    
    # Remove any trailing path components after the repo name
    # This handles URLs like: https://github.com/owner/repo/tree/main
    # Extract just the owner/repo part
    
    local owner=""
    local repo=""
    
    # Handle various GitHub URL formats
    # Pattern 1: SSH format (git@github.com:owner/repo.git or git@github.com:owner/repo)
    if [[ "$url" =~ ^git@github\.com:([^/]+)/([^/\.]+)(\.git)?/?.*$ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    # Pattern 2: HTTPS/HTTP format with or without protocol
    elif [[ "$url" =~ ^(https?://)?github\.com/([^/]+)/([^/\.]+)(\.git)?/?.*$ ]]; then
        owner="${BASH_REMATCH[2]}"
        repo="${BASH_REMATCH[3]}"
    # Pattern 3: Just owner/repo
    elif [[ "$url" =~ ^([^/@]+)/([^/\.]+)(\.git)?/?.*$ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    fi
    
    # If we successfully extracted owner and repo, build the normalized URL
    if [ -n "$owner" ] && [ -n "$repo" ]; then
        # Remove any .git extension from repo name
        repo="${repo%.git}"
        
        # Build standard HTTPS URL
        echo "https://github.com/$owner/$repo"
        return
    fi
    
    # If no pattern matched, return empty
    echo ""
}

# Get repository URL
get_repository_url() {
    if [ -n "$REPO_URL" ]; then
        # Normalize any provided URL
        local normalized=$(normalize_github_url "$REPO_URL")
        if [ -z "$normalized" ]; then
            log_error "Invalid GitHub repository URL format: $REPO_URL" >&2
            log_info "Expected format: https://github.com/owner/repository" >&2
            exit 1
        fi
        save_state "repo_type" "custom"
        echo "$normalized"
        return
    fi

    # Display to stderr so it shows even when captured
    {
        echo ""
        echo "=========================================="
        log_info "REPOSITORY SETUP"
        echo "=========================================="
        echo ""
        echo "Please select which repository you want to clone:"
        echo ""
        log_warning "Note: You must be a member of the appropriate Skool community to access these repositories"
        echo ""
        echo -e "${CYAN}Available Options:${NC}"
        echo ""
        echo -e "${GREEN}  1. Stack Masters Community (Free)${NC}"
        echo -e "     ${BLUE}Repository: https://github.com/AI-Stack-Masters/stack-community${NC}"
        echo -e "     ${BLUE}Membership: https://www.skool.com/ai-stack-masters${NC}"
        echo -e "     ${BLUE}Access: Free Skool community membership required${NC}"
        echo ""
        echo -e "${YELLOW}  2. Stack Masters Pro (Paid)${NC}"
        echo -e "     ${BLUE}Repository: https://github.com/AI-Stack-Master-Pros/stack-pro${NC}"
        echo -e "     ${BLUE}Membership: https://www.skool.com/ai-stack-master-pros${NC}"
        echo -e "     ${BLUE}Access: Paid Skool community membership required${NC}"
        echo ""
        echo -e "${CYAN}  3. Custom Repository${NC}"
        echo -e "     ${BLUE}Enter your own GitHub repository URL${NC}"
        echo ""
        echo "=========================================="
        echo ""
    } >&2

    read -p "$(echo -e ${GREEN}Enter your choice [1-3] \(default: 1\): ${NC})" choice

    if [ -z "$choice" ]; then
        choice="1"
    fi

    local normalized=""
    local repo_type="custom"

    case $choice in
        1)
            normalized="https://github.com/AI-Stack-Masters/stack-community"
            repo_type="free"
            log_success "Selected: Stack Masters Community (Free)" >&2
            ;;
        2)
            normalized="https://github.com/AI-Stack-Master-Pros/stack-pro"
            repo_type="pro"
            log_success "Selected: Stack Masters Pro (Paid)" >&2
            echo "" >&2
            log_warning "Pro repository requires an active paid membership at:" >&2
            echo "https://www.skool.com/ai-stack-master-pros" >&2
            ;;
        3)
            echo "" >&2
            log_info "Enter custom repository URL" >&2
            echo "" >&2
            log_info "Supported formats:" >&2
            echo "  - https://github.com/owner/repository" >&2
            echo "  - github.com/owner/repository" >&2
            echo "  - git@github.com:owner/repository.git" >&2
            echo "  - owner/repository" >&2
            echo "" >&2

            read -p "$(echo -e ${GREEN}Repository URL: ${NC})" url
            normalized=$(normalize_github_url "$url")

            if [ -z "$normalized" ]; then
                log_error "Invalid GitHub repository URL format: $url" >&2
                exit 1
            fi

            log_success "Normalized URL: $normalized" >&2
            repo_type="custom"
            ;;
        *)
            log_error "Invalid choice: $choice" >&2
            log_info "Please run the script again and select 1, 2, or 3" >&2
            exit 1
            ;;
    esac

    echo "" >&2

    # Save for recovery and error handling
    save_state "repo_type" "$repo_type"
    echo "$normalized"
}

# Prompt user for clone directory selection
prompt_clone_directory() {
    # System-wide defaults for PRODUCTION
    local system_dir
    local user_dir
    
    if [[ "$OS" == "macos" ]]; then
        # macOS - use /Users/Shared for multi-user access without sudo requirements
        system_dir="/Users/Shared/stack-masters"
        # macOS - use home directory for user software
        user_dir="$HOME/stack-masters"
    else
        # Linux (all distributions) - use /opt for system-wide software
        system_dir="/opt/stack-masters"
        # Linux - use home directory for user software
        user_dir="$HOME/stack-masters"
    fi
    
    echo ""
    log_info "Repository Clone Location"
    echo ""
    echo "Where would you like to clone the repository?"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT: Choose a location you'll use long-term${NC}"
    echo -e "${CYAN}This location will be used for:${NC}"
    echo "  • The Stack Masters repository and all its files"
    echo "  • Docker container volumes and configurations"
    echo "  • Future updates and maintenance operations"
    echo "  • Database files and application data"
    echo ""
    echo -e "${YELLOW}Note: Moving the repository later requires reconfiguring Docker containers${NC}"
    echo ""
    echo -e "${BLUE}For production use, option 1 (shared location) is strongly recommended.${NC}"
    echo ""
    echo "Repository name: $REPO_NAME"
    echo "Current directory: $(pwd)"
    echo ""
    echo "Options:"
    if [[ "$OS" == "macos" ]]; then
        echo -e "  1. $system_dir (recommended - shared, all users) ${GREEN}✓${NC}"
    else
        echo -e "  1. $system_dir (recommended - system-wide, all users) ${GREEN}✓${NC}"
    fi
    echo -e "  2. $user_dir (user-specific, limited access) ${YELLOW}⚠${NC}"
    echo "  3. $(pwd) (current directory)"
    echo "  4. Custom path"
    echo ""
    
    read -p "Enter choice [1-4] or custom path (default: 1): " choice
    
    case $choice in
        1|"")
            # DEFAULT: Shared/system-wide for production
            CLONE_BASE_DIR="$system_dir"
            if [[ "$OS" == "macos" ]]; then
                log_info "Shared location selected. This is the recommended choice for production deployments."
                echo ""
                echo -e "${CYAN}Note: /Users/Shared is macOS's standard location for shared data${NC}"
                echo -e "${CYAN}      • Accessible by all users without requiring admin privileges${NC}"
                echo -e "${CYAN}      • Docker Desktop will have full access to this directory${NC}"
                echo -e "${CYAN}      • Updates and maintenance can be performed easily${NC}"
            else
                log_info "System-wide location selected. This is the recommended choice for production deployments."
                echo ""
                echo -e "${CYAN}Note: /opt is Linux's standard location for optional software${NC}"
                echo -e "${CYAN}      • Docker containers will be accessible to all users${NC}"
                echo -e "${CYAN}      • System services can access this location${NC}"
                echo -e "${CYAN}      • May require sudo permissions for initial setup${NC}"
            fi
            echo ""
            ;;
        2)
            # User-specific with warning
            CLONE_BASE_DIR="$user_dir"
            log_warning "User-specific location selected. This may cause issues with Docker."
            echo ""
            echo -e "${YELLOW}⚠ Important limitations of user-specific locations:${NC}"
            echo -e "${YELLOW}  • Other users cannot access Docker containers${NC}"
            echo -e "${YELLOW}  • System services may fail to start${NC}"
            echo -e "${YELLOW}  • Updates may require additional permissions${NC}"
            echo -e "${YELLOW}  • Not recommended for production use${NC}"
            echo ""
            read -p "Press Enter to continue with this location or Ctrl+C to cancel..."
            ;;
        3)
            CLONE_BASE_DIR="$(pwd)"
            log_info "Using current directory: $(pwd)"
            echo ""
            echo -e "${CYAN}Note: Ensure this directory is accessible to Docker${NC}"
            echo ""
            ;;
        4)
            read -p "Enter custom path: " custom_path
            CLONE_BASE_DIR="$custom_path"
            log_info "Using custom path: $custom_path"
            echo ""
            echo -e "${CYAN}Note: Ensure this directory is accessible to Docker and other users if needed${NC}"
            echo ""
            ;;
        *)
            # Treat anything else as a custom path
            CLONE_BASE_DIR="$choice"
            log_info "Using custom path: $choice"
            echo ""
            echo -e "${CYAN}Note: Ensure this directory is accessible to Docker and other users if needed${NC}"
            echo ""
            ;;
    esac
    
    # Expand ~ to $HOME if present
    CLONE_BASE_DIR="${CLONE_BASE_DIR/#\~/$HOME}"
    
    # Set final clone directory
    CLONE_DIR="$CLONE_BASE_DIR/$REPO_NAME"
    
    # Validate and create parent directory
    validate_and_create_directory "$CLONE_BASE_DIR"
}

# Validate and create directory if needed
validate_and_create_directory() {
    local dir="$1"
    
    # Special handling for /Users/Shared on macOS
    if [[ "$OS" == "macos" ]] && [[ "$dir" =~ ^/Users/Shared/ ]]; then
        # Ensure /Users/Shared exists (it should on all macOS systems)
        if [ ! -d "/Users/Shared" ]; then
            log_error "/Users/Shared directory not found. This is unusual for macOS."
            log_info "You may need to create it with: sudo mkdir -p /Users/Shared"
            return 1
        fi
        
        # For /Users/Shared subdirectories, we typically don't need sudo
        if [ ! -d "$dir" ]; then
            if mkdir -p "$dir" 2>/dev/null; then
                log_success "Created shared directory: $dir"
                return 0
            else
                log_warning "Failed to create directory in /Users/Shared. Trying with elevated permissions..."
            fi
        elif [ -w "$dir" ]; then
            log_info "Using existing shared directory: $dir"
            return 0
        fi
    fi
    
    # Try to create directory - let the OS tell us if we need elevated permissions
    attempt_directory_creation() {
        local target_dir="$1"
        local with_sudo="$2"
        
        if [[ "$with_sudo" == "true" ]] && [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
            log_info "Attempting to create directory with elevated permissions..."
            if sudo mkdir -p "$target_dir" 2>/dev/null; then
                # Set ownership to current user for easier management
                # Skip for certain system directories that should remain root-owned
                if [[ ! "$target_dir" =~ ^/(System|usr/bin|usr/sbin|etc|lib|bin|sbin|boot|root)/ ]]; then
                    # On macOS, don't change ownership of /Users/Shared subdirectories
                    if [[ "$OS" != "macos" ]] || [[ ! "$target_dir" =~ ^/Users/Shared/ ]]; then
                        sudo chown -R "$USER:$(id -gn)" "$target_dir" 2>/dev/null || true
                    fi
                fi
                return 0
            fi
        else
            mkdir -p "$target_dir" 2>/dev/null
        fi
        return $?
    }
    
    # Check if directory already exists
    if [ -d "$dir" ]; then
        # Directory exists, check if we can write to it
        if [ -w "$dir" ]; then
            log_info "Using existing directory: $dir"
            return 0
        else
            # Directory exists but isn't writable
            log_warning "Directory exists but isn't writable: $dir"
            
            # Try to fix permissions with sudo if available
            if [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
                log_info "Attempting to fix permissions..."
                if sudo chown -R "$USER:$(id -gn)" "$dir" 2>/dev/null; then
                    log_success "Fixed permissions for existing directory: $dir"
                    return 0
                fi
            fi
            
            log_error "Cannot write to directory: $dir"
            log_info "Please choose a different location or fix permissions manually"
            exit 1
        fi
    fi
    
    # Directory doesn't exist, need to create it
    log_info "Creating directory: $dir"
    
    # First attempt: Try without sudo (works for most user directories)
    if attempt_directory_creation "$dir" "false"; then
        log_success "Created directory: $dir"
        return 0
    fi
    
    # First attempt failed - could be permissions issue
    # Second attempt: Try with sudo if available and we're not already root
    if [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
        if attempt_directory_creation "$dir" "true"; then
            log_success "Created directory with elevated permissions: $dir"
            return 0
        fi
    fi
    
    # Both attempts failed - provide helpful error message
    log_error "Failed to create directory: $dir"
    
    # Check why it might have failed
    local parent_dir=$(dirname "$dir")
    if [ ! -d "$parent_dir" ]; then
        log_error "Parent directory does not exist: $parent_dir"
        log_info "You may need to create the parent directory first or choose a different location"
    elif [ ! -w "$parent_dir" ]; then
        log_error "No write permission for parent directory: $parent_dir"
        if [ "$EUID" -ne 0 ]; then
            log_info "You may need administrator privileges for this location"
            log_info "Try running with sudo or choose a different location"
        fi
    else
        log_error "Unknown error creating directory"
    fi
    
    log_info ""
    log_info "Suggested alternatives:"
    log_info "  - Your home directory: $HOME/stack-masters"
    if [[ "$OS" == "macos" ]]; then
        log_info "  - Shared directory: /Users/Shared/stack-masters"
    fi
    log_info "  - Current directory: $(pwd)/stack-masters"
    if [[ "$OS" == "linux" ]] && [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
        log_info "  - Re-run the script with sudo if you need a system location"
    fi
    
    exit 1
}

# Helper function: Safe directory removal with retry logic
safe_remove_directory() {
    local dir="$1"
    local max_retries=3
    local retry_delay=2
    
    for i in $(seq 1 $max_retries); do
        log_info "Attempting to remove directory (attempt $i/$max_retries)..."
        
        # First, try to remove normally
        if rm -rf "$dir" 2>/dev/null; then
            # Verify it's actually gone
            if [ ! -d "$dir" ]; then
                log_success "Directory removed successfully"
                return 0
            fi
        fi
        
        # If we're here, removal failed
        log_warning "Directory removal failed, attempting recovery..."
        
        # Try to handle common issues
        if [[ "$OS" == "macos" ]]; then
            # macOS specific: Check for locked files
            if command -v chflags &>/dev/null; then
                log_info "Attempting to unlock files..."
                chflags -R nouchg "$dir" 2>/dev/null || true
            fi
        else
            # Linux: Check permissions
            if [ -w "$dir" ]; then
                # Try with sudo if available and we're not already root
                if [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
                    log_info "Attempting removal with elevated privileges..."
                    if sudo rm -rf "$dir" 2>/dev/null; then
                        if [ ! -d "$dir" ]; then
                            log_success "Directory removed with sudo"
                            return 0
                        fi
                    fi
                fi
            fi
        fi
        
        # Check if directory still exists
        if [ ! -d "$dir" ]; then
            log_success "Directory removed successfully"
            return 0
        fi
        
        # If still here, wait before retry
        if [ $i -lt $max_retries ]; then
            log_warning "Waiting $retry_delay seconds before retry..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # Exponential backoff
        fi
    done
    
    # All retries failed
    log_error "Failed to remove directory after $max_retries attempts"
    log_info "Manual intervention required. Please try:"
    echo "  1. Close any programs using files in: $dir"
    echo "  2. Check file permissions"
    echo "  3. Run manually: rm -rf \"$dir\""
    if [[ "$OS" != "macos" ]] && [ "$EUID" -ne 0 ]; then
        echo "  4. Or with sudo: sudo rm -rf \"$dir\""
    fi
    return 1
}

# Helper function: Clone with retry logic
clone_with_retry() {
    local repo_path="$1"
    local clone_dir="$2"
    local max_retries=3
    local retry_delay=2
    
    for i in $(seq 1 $max_retries); do
        log_info "Cloning repository (attempt $i/$max_retries)..."
        
        # Clear any partial clone
        if [ -d "$clone_dir" ]; then
            log_warning "Partial clone detected, cleaning up..."
            if ! safe_remove_directory "$clone_dir"; then
                return 1
            fi
        fi
        
        # Attempt clone - show progress to user
        log_info "Starting clone operation. This may take several minutes for large repositories..."
        echo ""
        
        # Run clone and let user see the progress naturally
        # Don't redirect stderr so git's progress bars work properly
        # Log the command being run for debugging
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Running: gh repo clone $repo_path $clone_dir" >> "$LOG_FILE" 2>/dev/null
        
        # Execute clone with proper terminal output for progress display
        gh repo clone "$repo_path" "$clone_dir"
        local clone_exit_code=$?
        
        # Log the result
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Clone exit code: $clone_exit_code" >> "$LOG_FILE" 2>/dev/null
        
        echo ""  # Add spacing after clone output
        
        # Verify clone actually succeeded with multiple checks
        if [ $clone_exit_code -eq 0 ]; then
            # Check for .git directory
            if [ -d "$clone_dir/.git" ]; then
                # Additional verification - check if git recognizes it as a valid repo
                if cd "$clone_dir" 2>/dev/null; then
                    if git status &>/dev/null; then
                        # Final check - ensure there are actual files
                        local file_count=$(find . -type f -not -path "./.git/*" 2>/dev/null | wc -l)
                        if [ $file_count -gt 0 ]; then
                            cd - >/dev/null
                            log_success "Repository cloned successfully"
                            return 0
                        else
                            cd - >/dev/null
                            log_warning "Clone appeared to succeed but no files found in repository"
                        fi
                    else
                        cd - >/dev/null
                        log_warning "Clone appeared to succeed but git status failed"
                    fi
                else
                    log_warning "Clone appeared to succeed but cannot access directory"
                fi
            else
                log_warning "Clone reported success but .git directory not found"
            fi
        fi
        
        # If we get here, clone failed
        log_warning "Clone failed (check output above for details)"
        
        # Check last few lines of log for SSL errors
        if [ -f "$LOG_FILE" ] && tail -n 10 "$LOG_FILE" | grep -qE "SSL|decryption failed|bad record mac"; then
            log_warning "SSL/TLS error detected. This could be caused by:"
            echo "  - Corporate proxy or firewall"
            echo "  - Antivirus software intercepting SSL"
            echo "  - Network connectivity issues"
            echo "  - Git SSL configuration"
            echo ""
            echo "Try running: git config --global http.sslVerify false"
            echo "Note: Only use this temporarily for testing!"
        fi
        
        # Check for common issues
        if ! gh auth status &>/dev/null; then
            log_error "GitHub authentication lost. Please run: gh auth login"
            return 1
        fi
        
        if ! ping -c 1 github.com &>/dev/null; then
            log_warning "Network connectivity issue detected"
        fi
        
        # Wait before retry
        if [ $i -lt $max_retries ]; then
            log_info "Waiting $retry_delay seconds before retry..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        fi
    done
    
    # All retries failed
    log_error "Failed to clone repository after $max_retries attempts"
    log_info "Please check:"
    echo "  1. Network connectivity: ping github.com"
    echo "  2. GitHub authentication: gh auth status"
    echo "  3. Repository access: gh repo view $repo_path"
    echo "  4. Disk space: df -h"
    return 1
}

# Clone appropriate repository
clone_repository() {
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        REPO_URL=$(get_repository_url)

        # Save state for recovery
        save_state "last_repo_url" "$REPO_URL"

        # Extract repository name from normalized URL (https://github.com/owner/repo)
        # Since URL is normalized, we can use simple extraction
        REPO_PATH="${REPO_URL#https://github.com/}"  # Remove prefix
        REPO_OWNER="${REPO_PATH%%/*}"                # Everything before first /
        REPO_NAME="${REPO_PATH#*/}"                  # Everything after first /

        log_info "Repository: $REPO_PATH"

        # Check if user has access to the repository
        if gh repo view "$REPO_PATH" &> /dev/null; then
            log_success "Access to $REPO_NAME confirmed!"
            break
        else
            log_error "Cannot access repository: $REPO_PATH"
            echo ""

            # Get the repository type from state
            local repo_type=$(get_state "repo_type")

            if [ "$repo_type" = "pro" ]; then
                # Pro repository access failed
                echo "=========================================="
                echo -e "${RED}   PRO MEMBERSHIP REQUIRED${NC}"
                echo "=========================================="
                echo ""
                log_warning "The Stack Masters Pro repository requires an active paid membership."
                echo ""
                echo -e "${CYAN}To access the Pro repository:${NC}"
                echo "  1. Join the paid Skool community at:"
                echo -e "     ${YELLOW}https://www.skool.com/ai-stack-master-pros${NC}"
                echo "  2. Complete your payment"
                echo "  3. Ensure your GitHub account is linked in Skool"
                echo ""
                echo -e "${CYAN}If you believe you already have access:${NC}"
                echo "  - Check your membership status at:"
                echo -e "    ${YELLOW}https://www.skool.com/ai-stack-master-pros${NC}"
                echo "  - Verify your GitHub account is correctly linked"
                echo "  - Reach out for help in the Skool community"
                echo ""
                echo "=========================================="
                echo ""
                echo -e "${YELLOW}Would you like to try the free version instead?${NC}"
                read -p "Type 'yes' to use Stack Masters Community (Free), or anything else to exit: " retry

                if [ "$retry" = "yes" ]; then
                    echo ""
                    log_info "Switching to Stack Masters Community (Free)..."
                    REPO_URL="https://github.com/AI-Stack-Masters/stack-community"
                    save_state "last_repo_url" "$REPO_URL"
                    save_state "repo_type" "free"
                    # Reset attempt counter and continue loop
                    attempt=1
                    continue
                else
                    log_info "Installation cancelled"
                    exit 0
                fi
            elif [ "$repo_type" = "free" ]; then
                # Free repository access failed
                echo "=========================================="
                echo -e "${RED}   COMMUNITY MEMBERSHIP REQUIRED${NC}"
                echo "=========================================="
                echo ""
                log_warning "The Stack Masters Community repository requires a free Skool membership."
                echo ""
                echo -e "${CYAN}To access the Community repository:${NC}"
                echo "  1. Join the free Skool community at:"
                echo -e "     ${YELLOW}https://www.skool.com/ai-stack-masters${NC}"
                echo "  2. Ensure your GitHub account is linked in Skool"
                echo ""
                echo -e "${CYAN}If you believe you already have access:${NC}"
                echo "  - Verify your GitHub account is correctly linked in Skool"
                echo "  - Reach out for help in the community at:"
                echo -e "    ${YELLOW}https://www.skool.com/ai-stack-masters${NC}"
                echo ""
                echo "=========================================="
                exit 1
            else
                # Custom repository access failed
                log_info "Please ensure:"
                echo "  1. You have access to this repository"
                echo "  2. Your GitHub authentication is working (gh auth status)"
                echo "  3. The repository URL is correct"

                if [ $attempt -lt $max_attempts ]; then
                    echo ""
                    log_warning "Please try again with a different URL (Attempt $attempt of $max_attempts)"
                    ((attempt++))
                else
                    log_error "Maximum attempts reached. Exiting."
                    exit 1
                fi
            fi
        fi
    done
    
    # Prompt user for clone directory
    prompt_clone_directory
    
    # Save state immediately after directory is chosen
    save_state "last_clone_dir" "$CLONE_DIR"
    
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
                if safe_remove_directory "$CLONE_DIR"; then
                    # Directory removed successfully, continue with clone
                    :
                else
                    log_error "Failed to remove existing directory"
                    echo ""
                    echo "Recovery options:"
                    echo "  1. Fix the issue manually and re-run the script"
                    echo "  2. Choose a different directory when prompted"
                    echo "  3. Run the script from a different location"
                    echo ""
                    read -p "Press Enter to exit and try again..." 
                    exit 1
                fi
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
    
    # Clone the repository with retry logic
    log_info "Starting repository clone process..."
    if clone_with_retry "$REPO_PATH" "$CLONE_DIR"; then
        log_success "Repository successfully cloned to: $CLONE_DIR"
        export STACK_DIR=$CLONE_DIR
    else
        log_error "Repository cloning failed"
        echo ""
        echo "Next steps:"
        echo "  1. Fix any issues mentioned above"
        echo "  2. Re-run this script: $0"
        echo "  3. Or manually clone: gh repo clone $REPO_PATH $CLONE_DIR"
        echo ""
        echo "For help, check the log file: $LOG_FILE"
        exit 1
    fi
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
    
    # Check disk space - check the actual clone location if available
    local check_path
    if [ -n "${CLONE_DIR:-}" ] && [ -d "${CLONE_DIR:-}" ]; then
        check_path="$CLONE_DIR"
    elif [[ "$OS" == "macos" ]]; then
        check_path="/Users/Shared"
    else
        check_path="/opt"
    fi
    
    if [[ "$OS" == "macos" ]]; then
        # macOS df output is different
        AVAILABLE_SPACE=$(df -g "$check_path" 2>/dev/null | tail -1 | awk '{print $4}')
    else
        AVAILABLE_SPACE=$(df -BG "$check_path" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
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
    echo ""
    echo ""
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
    
    # Determine path to check for disk space
    local check_path
    if [ -n "${CLONE_DIR:-}" ] && [ -d "${CLONE_DIR:-}" ]; then
        check_path="$CLONE_DIR"
    elif [[ "$OS" == "macos" ]]; then
        check_path="/Users/Shared"
    else
        check_path="/opt"
    fi
    
    if [[ "$OS" == "macos" ]]; then
        local free_space=$(df -g "$check_path" 2>/dev/null | tail -1 | awk '{print $4}')
        local total_mem=$(($(sysctl -n hw.memsize) / 1073741824))
    else
        local free_space=$(df -BG "$check_path" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
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
        # The generate-env-config.sh script is always at the same location in our controlled repository
        local env_script="$STACK_DIR/deploy/scripts/generate-env-config.sh"
        
        if [ -f "$env_script" ]; then
            if [ "$docker_ready" = true ]; then
                echo ""
                log_success "All components installed successfully!"
                echo ""
                log_info "Starting environment configuration..."
                local script_name="${env_script##*/}"
                echo "Running: $script_name"
                echo ""
                echo "=============================================="
                echo ""
                
                # Change to deploy/scripts directory where the script expects to be run
                cd "$STACK_DIR/deploy/scripts" || { log_error "Failed to change to $STACK_DIR/deploy/scripts"; exit 1; }
                
                # Execute the script from the deploy/scripts directory
                if bash "./generate-env-config.sh"; then
                    log_success "Environment configuration completed"
                else
                    log_warning "Environment configuration script encountered issues but continuing..."
                fi
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
                echo "     cd $STACK_DIR/deploy/scripts"
                echo "     ./generate-env-config.sh"
            fi
        else
            echo ""
            log_success "Installation completed!"
            echo ""
            log_warning "generate-env-config.sh not found at expected location"
            log_info "Expected at: $STACK_DIR/deploy/scripts/generate-env-config.sh"
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

# Progress tracking
STEPS_TOTAL=8
STEP_CURRENT=0
STEPS_SKIPPED=0

show_progress() {
    local step_name="$1"
    local is_skipped="${2:-false}"
    
    if [ "$is_skipped" = "true" ]; then
        STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
        STEPS_TOTAL=$((STEPS_TOTAL - 1))
        return
    fi
    
    STEP_CURRENT=$((STEP_CURRENT + 1))
    local adjusted_current=$((STEP_CURRENT))
    local adjusted_total=$((STEPS_TOTAL))
    
    echo ""
    echo "=============================================="
    echo -e "${BLUE}Step $adjusted_current of $adjusted_total: $step_name${NC}"
    echo "=============================================="
    echo ""
    save_state "current_step" "$STEP_CURRENT"
    save_state "current_step_name" "$step_name"
}

# Cleanup function for interruptions
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_warning "Setup interrupted or failed!"
        
        local current_step=$(get_state "current_step_name")
        if [ -n "$current_step" ]; then
            echo "Failed at step: $current_step"
        fi
        
        echo ""
        echo "Recovery options:"
        echo "  1. Check the log file for details: $LOG_FILE"
        echo "  2. Fix any issues mentioned above"
        echo "  3. Re-run the script to continue: $0"
        echo ""
        
        # Save current state for recovery
        if [ -n "$REPO_URL" ]; then
            save_state "last_repo_url" "$REPO_URL"
        fi
        if [ -n "${CLONE_DIR:-}" ]; then
            save_state "last_clone_dir" "$CLONE_DIR"
        fi
    else
        # Success - clear state
        clear_state
        echo ""
        log_success "Setup completed successfully!"
    fi
}

# Set up signal handlers
trap cleanup_on_exit EXIT
trap 'echo ""; log_warning "Setup interrupted by user"; exit 130' INT TERM

# Main installation flow
main() {
    clear
    
    echo "=============================================="
    echo "   Stack Masters Setup Script v${VERSION}"
    echo "=============================================="
    echo ""
    
    # Check for previous incomplete setup
    local last_repo=$(get_state "last_repo_url")
    local last_dir=$(get_state "last_clone_dir")
    if [ -n "$last_repo" ] || [ -n "$last_dir" ]; then
        log_warning "Previous setup was interrupted"
        echo "Last attempted repository: ${last_repo:-unknown}"
        echo "Last attempted directory: ${last_dir:-unknown}"
        echo ""
        read -p "Continue with previous setup? [Y/n]: " continue_prev
        if [[ "$continue_prev" =~ ^[Yy]?$ ]]; then
            REPO_URL="$last_repo"
            CLONE_DIR="$last_dir"
        else
            clear_state
        fi
        echo ""
    fi
    
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
    echo "     - Prepare system environment for Stack Masters"
    echo ""
    
    echo "  GitHub Setup:"
    if [ "$SKIP_AUTH" != "true" ]; then
        if [ "$gh_authenticated" = "yes" ]; then
            echo -e "     ${GREEN}[OK] Already authenticated with GitHub${NC}"
        else
            echo "     - Authenticate with GitHub"
        fi
    fi
    echo "     - Clone repository to your chosen directory"
    echo ""
    
    echo "  Final Steps:"
    echo "     - Validate installation"
    echo "     - Check system resources"
    echo ""
    
    # Get confirmation unless auto-confirm is set
    if [ "$AUTO_CONFIRM" != "true" ]; then
        echo -e "${YELLOW}Do you want to proceed with the installation?${NC}"
        read -p "Type 'yes' to continue or anything else to exit: " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            log_warning "Installation cancelled by user"
            exit 0
        fi
    else
        log_info "Auto-confirm mode enabled, proceeding with installation..."
    fi
    
    echo ""
    log_info "Starting Stack Masters setup..."
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # Check if we need to install anything
    local needs_packages=false
    
    # Quick check if anything needs to be installed
    if ! check_all_requirements; then
        needs_packages=true
        log_info "Some packages need to be installed"
    else
        log_info "All required packages are already installed - skipping system updates"
    fi
    
    # Only update system packages if we need to install something
    if [ "$needs_packages" = true ]; then
        show_progress "Updating system packages"
        update_system
    else
        log_info "Skipping package manager updates - all requirements already met"
    fi
    
    # Only install core deps if they're missing
    if ! check_core_deps; then
        show_progress "Installing core dependencies"
        install_core_deps
    else
        log_info "Core dependencies already installed - skipping"
    fi
    
    # Install components (these functions already check if installed)
    show_progress "Installing Git"
    install_git
    
    show_progress "Installing GitHub CLI"
    install_github_cli
    
    show_progress "Installing Docker"
    install_docker
    
    # GitHub authentication and repository setup
    show_progress "Setting up GitHub authentication"
    github_auth
    
    show_progress "Cloning repository"
    clone_repository
    
    # Validate installation
    show_progress "Validating installation"
    validate_system
    
    # Show summary
    show_summary
}

# Run main function
main "$@"