# Stack Masters WordPress-Like Setup Solution

## Vision: Bulletproof One-Command Installation

Transform Stack Masters installation into a foolproof experience where platform-specific setup scripts validate everything upfront, then launch a web wizard that handles the rest—just like WordPress installers.

### User Experience Flow
1. **Run platform-specific command**:
   - Linux/Mac: `curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh | bash`
   - Windows: `.\setup-windows.ps1`
2. **Script validates everything**: All dependencies, network, disk space, ports, Docker
3. **See clear instructions**: "✅ All checks passed! Open http://YOUR-IP:8080 in your browser"
4. **Complete setup in browser**: Smooth wizard experience with no surprises
5. **Stack deployed**: Everything works first time

## Architecture

```
┌─────────────────────────────┐
│   Platform Setup Script     │ (setup.sh / setup-windows.ps1)
│ ✓ Detect OS and environment │
│ ✓ System requirements check │
│ ✓ Install dependencies      │
│ ✓ Platform-specific config  │
│ ✓ Start wizard on host      │
│ ✓ Show access URLs         │
└────────┬───────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Web Wizard (Node.js)      │ Running directly on host
│ ┌─────────────────────────┐ │
│ │   Pre-built Frontend    │ │ (React dist/ folder)
│ │   - Welcome screen      │ │
│ │   - GitHub auth UI      │ │
│ │   - Repository selector │ │
│ │   - Configuration form  │ │
│ │   - Progress monitor    │ │
│ └───────────┬─────────────┘ │
│             │ API calls      │
│ ┌───────────▼─────────────┐ │
│ │   Backend (Node.js)     │ │
│ │   - Serves frontend     │ │
│ │   - Platform detection  │ │
│ │   - Docker operations   │ │
│ │   - System commands     │ │
│ │   - File operations     │ │
│ └─────────────────────────┘ │
└────────┬───────────────────┘
         │ Host system access
         ▼
┌─────────────────────────────┐
│     Host System             │
│ - Docker daemon             │
│ - File system              │
│ - Network configuration    │
│ - GitHub CLI               │
└────────┬───────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Deployed Stack            │ (Docker Compose)
│ - All services containerized│
│ - Isolated from wizard      │
└─────────────────────────────┘
```

## Platform-Specific Challenges & Solutions

### Cross-Platform Issues
1. **Docker Access**: Different on Windows (named pipes) vs Linux (unix socket)
2. **Path Formats**: Windows paths need translation for WSL2/Docker
3. **Firewall Commands**: Completely different across platforms
4. **Permissions**: Root/sudo on Linux, Administrator on Windows
5. **Package Managers**: apt/yum/dnf/pacman/zypper vs winget/chocolatey

### Solution: Platform-Aware Architecture
- Setup scripts handle ALL platform-specific operations
- Wizard uses abstraction layer for cross-platform commands
- Critical system changes stay in setup scripts
- Wizard focuses on configuration and orchestration

## What Needs to Change

### 1. Enhanced Setup Scripts (setup.sh / setup-windows.ps1)

#### Comprehensive Validation Functions:

```bash
# Complete system validation before starting wizard
validate_system_requirements() {
    log_info "Running comprehensive system checks..."
    
    # Check disk space (need at least 20GB)
    AVAILABLE_SPACE=$(df -BG /opt 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 20 ]; then
        log_error "Insufficient disk space: ${AVAILABLE_SPACE}GB available, 20GB required"
        exit 1
    fi
    log_success "Disk space: ${AVAILABLE_SPACE}GB available ✓"
    
    # Check memory (need at least 4GB)
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 4 ]; then
        log_error "Insufficient memory: ${TOTAL_MEM}GB available, 4GB required"
        exit 1
    fi
    log_success "Memory: ${TOTAL_MEM}GB available ✓"
    
    # Check CPU cores (recommend at least 2)
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "Only $CPU_CORES CPU core(s) detected. Performance may be limited."
    else
        log_success "CPU cores: $CPU_CORES ✓"
    fi
}

# Validate Docker is working properly
validate_docker() {
    log_info "Validating Docker installation..."
    
    # Check Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null
        sleep 3
        if ! docker info >/dev/null 2>&1; then
            log_error "Failed to start Docker daemon"
            exit 1
        fi
    fi
    
    # Test Docker with hello-world
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        log_error "Docker test failed. Please check Docker installation."
        exit 1
    fi
    log_success "Docker daemon running ✓"
    
    # Check Docker Compose
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        log_success "Docker Compose (v2) available ✓"
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose (v1) available ✓"
    else
        log_error "Docker Compose not found"
        exit 1
    fi
}

# Check network and ports
validate_network() {
    log_info "Checking network configuration..."
    
    # Check if port 8080 is available
    if lsof -i:8080 >/dev/null 2>&1 || netstat -tuln | grep -q ":8080 "; then
        log_error "Port 8080 is already in use"
        log_info "Please free up port 8080 or stop the service using it"
        exit 1
    fi
    log_success "Port 8080 available ✓"
    
    # Check other required ports
    REQUIRED_PORTS=(80 443 3000 5678 9090)
    for port in "${REQUIRED_PORTS[@]}"; do
        if lsof -i:$port >/dev/null 2>&1 || netstat -tuln | grep -q ":$port "; then
            log_warning "Port $port is in use. This may cause conflicts."
        fi
    done
    
    # Test internet connectivity
    if ! curl -s --head https://github.com >/dev/null; then
        log_error "No internet connectivity detected"
        exit 1
    fi
    log_success "Internet connectivity ✓"
}
```

#### Environment Detection:
```bash
# Detect if desktop or server environment
detect_environment() {
    if [[ -n "$DISPLAY" ]] || [[ -n "$DESKTOP_SESSION" ]]; then
        # Desktop - use localhost
        export HOST="localhost"
    else
        # Server - bind to all interfaces
        export HOST="0.0.0.0"
    fi
}

# Show appropriate access URLs
show_access_urls() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Stack Masters Setup Wizard Ready!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Open your web browser and go to:"
    
    if [[ "$HOST" == "localhost" ]]; then
        echo "  → http://localhost:8080"
    else
        # Show all possible URLs for server mode
        echo "  → http://localhost:8080 (from this machine)"
        LOCAL_IP=$(hostname -I | awk '{print $1}')
        echo "  → http://$LOCAL_IP:8080 (from local network)"
        PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null)
        if [[ -n "$PUBLIC_IP" ]]; then
            echo "  → http://$PUBLIC_IP:8080 (from internet)"
        fi
    fi
    echo ""
    echo "The wizard will guide you through:"
    echo "  ✓ GitHub authentication"
    echo "  ✓ Repository selection" 
    echo "  ✓ Configuration"
    echo "  ✓ Deployment"
}
```

### 2. Zero-Build Installation Strategy

#### Approach: Pre-built Assets + Minimal Dependencies
```bash
# Frontend: Pre-built React app
cd apps/provisioning-web/frontend
npm install
npm run build
# Commit dist/ folder to repository

# Backend: Minimal dependencies with lockfile
cd apps/provisioning-web/backend
npm install --production
npm prune --production
# Commit package-lock.json (NOT node_modules)
```

#### Why Not Docker for the Wizard?
- **Docker-in-Docker complexity**: Wizard needs to run Docker commands
- **Host access required**: File system, network config, firewall
- **Platform differences**: Docker Desktop on Windows/Mac vs native on Linux
- **Security concerns**: Would need --privileged flag

#### Repository Structure:
```
apps/provisioning-web/
├── frontend/
│   ├── dist/              # ← Pre-built React app (committed)
│   │   ├── index.html
│   │   ├── assets/
│   │   └── ...
├── backend/
│   ├── package.json       # ← Minimal dependencies
│   ├── package-lock.json  # ← Exact versions (committed)
│   ├── server.js          # ← Main server
│   └── platform/          # ← Platform abstraction
│       ├── base.js
│       ├── linux.js
│       ├── windows.js
│       └── darwin.js
```

#### Fast Installation in Setup Script:
```bash
# Quick npm ci for deterministic install
cd /opt/wizard/backend
npm ci --production  # Uses package-lock.json
# Takes ~30 seconds with minimal deps
```

### 3. Provisioning Web Backend Changes

#### Platform Abstraction Layer:
```javascript
// platform/base.js
class PlatformBase {
    async runDockerCompose(action, cwd) {
        throw new Error('Must be implemented by platform');
    }
    
    async openFirewallPort(port) {
        throw new Error('Must be implemented by platform');
    }
    
    async writeSystemFile(path, content) {
        // Common implementation
        return fs.writeFileSync(path, content);
    }
}

// platform/linux.js
class LinuxPlatform extends PlatformBase {
    async runDockerCompose(action, cwd) {
        return exec(`docker compose ${action}`, { cwd });
    }
    
    async openFirewallPort(port) {
        if (await commandExists('ufw')) {
            return exec(`ufw allow ${port}/tcp`);
        } else if (await commandExists('firewall-cmd')) {
            return exec(`firewall-cmd --permanent --add-port=${port}/tcp`);
        }
    }
}

// platform/windows.js
class WindowsPlatform extends PlatformBase {
    async runDockerCompose(action, cwd) {
        // Handle WSL2 path translation
        const wslPath = cwd.replace(/\\/g, '/').replace(/^([A-Z]):/, '/mnt/$1'.toLowerCase());
        return exec(`wsl docker compose ${action}`, { cwd: wslPath });
    }
    
    async openFirewallPort(port) {
        return exec(`New-NetFirewallRule -DisplayName "Stack Masters ${port}" -Direction Inbound -Protocol TCP -LocalPort ${port} -Action Allow`, {
            shell: 'powershell.exe'
        });
    }
}
```

#### Update Server Binding:
```javascript
// Detect environment and bind appropriately
const HOST = process.env.HOST || (isDesktopEnvironment() ? 'localhost' : '0.0.0.0');
const PORT = process.env.PORT || 8080;

// Initialize platform handler
const platform = PlatformFactory.create(process.platform);

server.listen(PORT, HOST, () => {
    displayAccessUrls(HOST, PORT);
});

## Implementation Checklist

### Phase 1: Setup Script Enhancements
- [ ] Add comprehensive system validation functions
- [ ] Implement disk space checks (20GB minimum)
- [ ] Add memory validation (4GB minimum)
- [ ] Verify all required ports are available
- [ ] Test Docker daemon health
- [ ] Add network connectivity checks
- [ ] Install minimal Node.js runtime
- [ ] Keep platform-specific firewall configuration
- [ ] Add detailed error messages for each failure

### Phase 2: Platform Abstraction Layer
- [ ] Create platform/base.js with common interface
- [ ] Implement platform/linux.js for Linux operations
- [ ] Implement platform/windows.js with WSL2 support
- [ ] Implement platform/darwin.js for macOS
- [ ] Add Docker command abstraction
- [ ] Add path translation for Windows/WSL2
- [ ] Create PlatformFactory for runtime selection
- [ ] Add comprehensive platform detection

### Phase 3: Backend Architecture Updates
- [ ] Remove Docker containerization for wizard
- [ ] Update server to run directly on host
- [ ] Add platform-aware command execution
- [ ] Implement /api/github/device-auth endpoint
- [ ] Add /api/github/repositories endpoint
- [ ] Add /api/github/clone endpoint
- [ ] Add /api/system/validate endpoint
- [ ] Implement real-time progress streaming

### Phase 4: Frontend Pre-compilation
- [ ] Build production React bundle
- [ ] Optimize assets (minimize, compress)
- [ ] Generate source maps
- [ ] Commit dist/ folder to repository
- [ ] Add dist/ to repository (remove from .gitignore)
- [ ] Verify frontend loads without build step

### Phase 5: Minimal Dependencies
- [ ] Audit backend dependencies
- [ ] Remove unnecessary packages
- [ ] Create minimal package.json
- [ ] Generate package-lock.json
- [ ] Test npm ci --production speed
- [ ] Document exact dependency list

### Phase 6: Testing & Validation
- [ ] Test on Ubuntu 20.04/22.04
- [ ] Test on Windows Server 2022
- [ ] Test on Windows 11 Desktop
- [ ] Test on RHEL/CentOS/Rocky Linux
- [ ] Test on macOS (if applicable)
- [ ] Verify remote browser access
- [ ] Test firewall configuration
- [ ] Validate GitHub authentication flow

## Security Notes

1. **Temporary Wizard**: Only runs during initial setup
2. **Network Binding**: 
   - Desktop: localhost only (secure)
   - Server: 0.0.0.0 (needed for remote access)
3. **Token Handling**: GitHub tokens stored in memory only
4. **Firewall**: Port 8080 only open during setup

## Testing Scenarios

### Desktop Install:
1. Run setup script on machine with GUI
2. Verify wizard only accessible on localhost
3. Complete full flow
4. Verify stack deployment

### Server Install:
1. Run setup script on headless server
2. Verify wizard accessible remotely
3. Test from different client machines
4. Complete full flow
5. Verify stack deployment

### Network Variations:
- Behind NAT
- Direct public IP
- VPN connections
- Firewall restrictions

## Success Criteria

- One command to start
- Zero CLI prompts after initial script
- Clear instructions for any environment
- Works on desktop and server
- Beautiful, intuitive web interface
- Successful deployment in < 5 minutes

---

## Key Architectural Decisions

### Why Run Wizard on Host (Not Docker)?
1. **Docker Access**: Wizard needs to deploy Docker containers - Docker-in-Docker is complex
2. **System Configuration**: Direct firewall, network, and file system access required
3. **Platform Differences**: Docker Desktop on Windows/Mac behaves differently than Linux
4. **Security**: Avoids dangerous --privileged flag that would be required
5. **Simplicity**: Same trust model as WordPress installers

### Why Platform-Specific Setup Scripts?
1. **Firewall Commands**: Totally different across platforms (ufw vs firewall-cmd vs netsh)
2. **Package Managers**: Each OS has unique package management
3. **Permission Models**: sudo/root vs Administrator
4. **Path Handling**: Windows paths need WSL2 translation
5. **Better UX**: Native commands and error messages

### Why Pre-built Frontend?
1. **Zero Build Time**: Users don't wait for React compilation
2. **No Build Failures**: Eliminates npm build errors
3. **Predictable**: Same assets for every installation
4. **Smaller Dependencies**: Backend only needs runtime packages
5. **WordPress-Like**: Instant start, just like WordPress

### Why Not Commit node_modules?
1. **Repository Size**: Would add 100MB+ to repo
2. **Platform Issues**: Some modules have native bindings
3. **Security**: Harder to audit committed dependencies
4. **Better Solution**: npm ci with lockfile is fast and deterministic

This architecture prioritizes reliability, simplicity, and a WordPress-like user experience while maintaining security and cross-platform compatibility.