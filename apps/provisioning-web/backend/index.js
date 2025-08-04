#!/usr/bin/env node

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3003;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Serve static frontend files
const frontendBuildPath = path.join(__dirname, '../frontend/build');
if (fs.existsSync(frontendBuildPath)) {
    app.use(express.static(frontendBuildPath));
}

// Store active provisioning sessions
const activeSessions = new Map();

// Utility functions
function generateSecurePassword() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
    return Array.from({ length: 16 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

function generateJWTSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return Array.from({ length: 64 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

// Get public IP
async function getPublicIP() {
    try {
        const { execSync } = require('child_process');
        const ip = execSync('curl -s https://ipinfo.io/ip', { timeout: 5000 }).toString().trim();
        return ip;
    } catch (error) {
        return null;
    }
}

// API Routes

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Get public IP
app.get('/api/public-ip', async (req, res) => {
    try {
        const publicIP = await getPublicIP();
        if (publicIP) {
            res.json({ publicIP });
        } else {
            res.status(500).json({ error: 'Unable to determine public IP' });
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Validate DNS records
app.post('/api/validate-dns', async (req, res) => {
    const { domain } = req.body;
    
    if (!domain) {
        return res.status(400).json({ error: 'Domain is required' });
    }

    try {
        const publicIP = await getPublicIP();
        if (!publicIP) {
            return res.status(500).json({ error: 'Unable to determine server public IP' });
        }

        const { execSync } = require('child_process');
        const records = [
            { domain: domain, expectedIP: publicIP },
            { domain: `grafana.${domain}`, expectedIP: publicIP },
            { domain: `n8n.${domain}`, expectedIP: publicIP },
            { domain: `stack.${domain}`, expectedIP: publicIP }
        ];

        let allValid = true;
        for (let record of records) {
            try {
                const output = execSync(`dig +short ${record.domain} A`, { timeout: 5000 }).toString().trim();
                const ips = output.split('\n').filter(ip => ip && /^\d+\.\d+\.\d+\.\d+$/.test(ip));
                
                record.actualIPs = ips;
                record.valid = ips.includes(record.expectedIP);
                
                if (!record.valid) {
                    allValid = false;
                }
            } catch (error) {
                record.actualIPs = [];
                record.valid = false;
                record.error = error.message;
                allValid = false;
            }
        }

        res.json({
            publicIP,
            valid: allValid,
            records
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Generate SSL certificates (mock for demo)
app.post('/api/generate-ssl', (req, res) => {
    const { domain, email } = req.body;
    
    if (!domain || !email) {
        return res.status(400).json({ error: 'Domain and email are required' });
    }

    // Mock SSL generation
    const certificates = [
        domain,
        `grafana.${domain}`,
        `n8n.${domain}`,
        `stack.${domain}`
    ];

    res.json({
        message: 'SSL certificate generation initiated',
        email,
        certificates
    });
});

// Configure environment
app.post('/api/configure', (req, res) => {
    const { domain, adminEmail, adminPassword } = req.body;
    
    if (!domain || !adminEmail) {
        return res.status(400).json({ error: 'Domain and admin email are required' });
    }

    try {
        // Generate secure credentials if not provided
        const password = adminPassword || generateSecurePassword();
        const jwtSecret = generateJWTSecret();
        const serviceRoleKey = generateJWTSecret();
        const anonKey = generateJWTSecret();

        // Generate .env configuration
        const envConfig = `# N8N Monitoring Stack - Environment Configuration

############
# Project/General Settings
############
COMPOSE_PROJECT_NAME=n8n-monitoring
DOMAIN=${domain}
TZ=America/Chicago

############
# Secrets (REQUIRED for Supabase Image Compatibility)
############
JWT_SECRET=${jwtSecret}
SERVICE_ROLE_KEY=${serviceRoleKey}
ANON_KEY=${anonKey}

############
# UNIFIED AUTHENTICATION CONFIGURATION
############
# Master admin credentials for all services
MASTER_ADMIN_EMAIL=${adminEmail}
MASTER_ADMIN_PASSWORD=${password}

# Enable Supabase authentication for n8n
N8N_SUPABASE_AUTH_ENABLED=true

# Supabase connection settings
SUPABASE_URL=http://app-stackmanager-ui:80
SUPABASE_ANON_KEY=\${ANON_KEY}
SUPABASE_SERVICE_KEY=\${SERVICE_ROLE_KEY}

############
# Database Configuration
############
POSTGRES_DB=n8n_monitoring
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=${generateSecurePassword()}

############
# Stack Manager Configuration
############
STACK_MANAGER_API_PORT=3002
STACK_MANAGER_UI_PORT=3001

############
# n8n Configuration
############
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_HOST=${domain}

############
# Monitoring Configuration
############
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
LOKI_PORT=3100

############
# Security Configuration
############
MITMPROXY_SSL_INSECURE=false
`;

        // Save to file (in production, you'd want proper file handling)
        const projectRoot = path.resolve(__dirname, '../../..');
        const envPath = path.join(projectRoot, '.env');
        
        fs.writeFileSync(envPath, envConfig);

        res.json({
            success: true,
            message: 'Configuration saved successfully',
            envPath: envPath,
            credentials: {
                domain,
                adminEmail,
                adminPassword: password
            }
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Start provisioning with Server-Sent Events
app.get('/api/provision', (req, res) => {
    const sessionId = uuidv4();
    const timeout = parseInt(req.query.timeout) || 300;
    const skipSteps = req.query.skipSteps ? req.query.skipSteps.split(',') : [];

    // Set up SSE
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Cache-Control'
    });

    const sendEvent = (data) => {
        res.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    // Start provisioning process
    const projectRoot = path.resolve(__dirname, '../../..');
    const startupScript = path.join(projectRoot, 'startup.sh');

    sendEvent({
        status: 'started',
        message: 'Initializing provisioning process...',
        sessionId,
        phase: 'initialization',
        progress: 0
    });

    // Check if startup script exists
    if (!fs.existsSync(startupScript)) {
        sendEvent({
            status: 'failed',
            message: 'Startup script not found',
            error: `Script not found at ${startupScript}`
        });
        res.end();
        return;
    }

    // Build startup command
    let args = ['--clean'];
    if (timeout !== 300) {
        args.push('--timeout', timeout.toString());
    }
    if (skipSteps.length > 0) {
        args.push('--skip-steps', skipSteps.join(','));
    }

    sendEvent({
        status: 'running',
        message: `Executing: ${startupScript} ${args.join(' ')}`,
        phase: 'startup',
        progress: 10
    });

    // Execute startup script
    const child = spawn(startupScript, args, {
        cwd: projectRoot,
        stdio: ['ignore', 'pipe', 'pipe']
    });

    activeSessions.set(sessionId, { process: child, startTime: Date.now() });

    let progress = 10;
    const phases = [
        'cleanup', 'pull-core', 'pull-monitoring', 'pull-apps', 
        'build-custom', 'verify-images', 'start-stack', 'wait-healthy', 'verify-services'
    ];
    let currentPhaseIndex = 0;

    // Handle stdout
    child.stdout.on('data', (data) => {
        const output = data.toString();
        
        // Update progress based on phase detection
        for (let i = 0; i < phases.length; i++) {
            if (output.toLowerCase().includes(phases[i])) {
                currentPhaseIndex = i;
                progress = Math.min(10 + (i * 10), 90);
                break;
            }
        }

        sendEvent({
            status: 'running',
            message: output.trim(),
            phase: phases[currentPhaseIndex] || 'provisioning',
            progress
        });
    });

    // Handle stderr
    child.stderr.on('data', (data) => {
        const output = data.toString();
        sendEvent({
            status: 'warning',
            message: output.trim(),
            phase: phases[currentPhaseIndex] || 'provisioning',
            progress
        });
    });

    // Handle process completion
    child.on('close', (code) => {
        activeSessions.delete(sessionId);
        
        if (code === 0) {
            sendEvent({
                status: 'complete',
                message: 'Provisioning completed successfully!',
                phase: 'complete',
                progress: 100,
                urls: {
                    'Stack Manager': `http://localhost:3001`,
                    'Grafana': `http://localhost:3000`,
                    'n8n': `https://localhost:5678`,
                    'Prometheus': `http://localhost:9090`
                }
            });
        } else {
            sendEvent({
                status: 'failed',
                message: `Provisioning failed with exit code ${code}`,
                phase: 'failed',
                canRetry: true
            });
        }
        
        res.end();
    });

    // Handle client disconnect
    req.on('close', () => {
        if (activeSessions.has(sessionId)) {
            const session = activeSessions.get(sessionId);
            session.process.kill('SIGTERM');
            activeSessions.delete(sessionId);
        }
    });

    // Timeout handling
    setTimeout(() => {
        if (activeSessions.has(sessionId)) {
            const session = activeSessions.get(sessionId);
            session.process.kill('SIGTERM');
            activeSessions.delete(sessionId);
            
            sendEvent({
                status: 'failed',
                message: `Provisioning timed out after ${timeout} seconds`,
                phase: 'timeout',
                canRetry: true
            });
            res.end();
        }
    }, timeout * 1000);
});

// Get active sessions
app.get('/api/sessions', (req, res) => {
    const sessions = Array.from(activeSessions.entries()).map(([id, session]) => ({
        id,
        startTime: session.startTime,
        duration: Date.now() - session.startTime,
        pid: session.process.pid
    }));
    
    res.json({ sessions });
});

// Serve React app for all other routes
app.get('*', (req, res) => {
    const indexPath = path.join(frontendBuildPath, 'index.html');
    if (fs.existsSync(indexPath)) {
        res.sendFile(indexPath);
    } else {
        res.status(404).json({ error: 'Frontend not built. Run npm run build in frontend directory.' });
    }
});

// Error handling
app.use((err, req, res, next) => {
    console.error('Server error:', err);
    res.status(500).json({ error: err.message });
});

// Start server
app.listen(PORT, () => {
    console.log(`🚀 AI Stack Masters Provisioning Backend running on port ${PORT}`);
    console.log(`📍 Access the interface at: http://localhost:${PORT}`);
    console.log(`📋 API endpoints available at: http://localhost:${PORT}/api/*`);
});

module.exports = app;