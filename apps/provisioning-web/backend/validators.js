const dns = require('dns').promises;
const { URL } = require('url');

/**
 * Validate domain format and accessibility
 */
async function validateDomain(domain) {
  const errors = [];
  const warnings = [];
  
  // Basic format validation
  const domainRegex = /^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.)*[a-zA-Z]{2,}$/;
  if (!domainRegex.test(domain)) {
    errors.push('Invalid domain format. Domain must contain only letters, numbers, and hyphens.');
    return { valid: false, errors, warnings };
  }
  
  // Check if it's localhost or local domain
  if (domain === 'localhost' || domain.endsWith('.local') || domain.endsWith('.test')) {
    warnings.push('Using local domain. This will only be accessible from this machine.');
    return { valid: true, errors, warnings };
  }
  
  // Check if domain resolves
  try {
    const addresses = await dns.resolve4(domain);
    if (addresses.length > 0) {
      warnings.push(`Domain resolves to: ${addresses.join(', ')}`);
    }
  } catch (error) {
    if (error.code === 'ENOTFOUND') {
      warnings.push('Domain does not currently resolve. Make sure DNS is configured before accessing services.');
    } else {
      warnings.push(`DNS lookup warning: ${error.message}`);
    }
  }
  
  return { valid: true, errors, warnings };
}

/**
 * Check for port conflicts with existing services
 */
async function checkPortConflicts(config) {
  const net = require('net');
  
  const defaultPorts = {
    'Stack Manager UI': 3001,
    'Stack Manager API': 3002,
    'Grafana': 3000,
    'n8n': 5678,
    'Prometheus': 9090,
    'GoTrue Auth': 9999,
    'PostgreSQL': 5433,
    'Loki': 3100
  };
  
  const conflicts = [];
  
  for (const [service, port] of Object.entries(defaultPorts)) {
    const isInUse = await new Promise((resolve) => {
      const server = net.createServer();
      server.once('error', () => resolve(true));
      server.once('listening', () => {
        server.close();
        resolve(false);
      });
      server.listen(port, '127.0.0.1');
    });
    
    if (isInUse) {
      conflicts.push({
        service,
        port,
        message: `Port ${port} is already in use (required for ${service})`
      });
    }
  }
  
  return conflicts;
}

/**
 * Validate service URLs and check propagation
 */
async function validateServiceUrls(config) {
  const urls = [];
  const domain = config.domain || 'localhost';
  const protocol = config.sslProvider !== 'none' ? 'https' : 'http';
  
  // Build expected URLs
  const services = [
    { name: 'n8n', path: '', port: 5678, protocol: 'https' }, // n8n always uses https
    { name: 'Grafana', path: '', port: 3000, protocol: 'http' },
    { name: 'Stack Manager', path: '', port: 3001, protocol: 'http' },
    { name: 'Prometheus', path: '', port: 9090, protocol: 'http' }
  ];
  
  for (const service of services) {
    const url = `${service.protocol}://${domain}:${service.port}${service.path}`;
    urls.push({
      service: service.name,
      url,
      port: service.port,
      expectedStatus: 'accessible after deployment'
    });
  }
  
  return urls;
}

/**
 * Check if environment will cause conflicts
 */
async function validateEnvironment() {
  const issues = [];
  
  // Check Docker
  try {
    const { execSync } = require('child_process');
    execSync('docker --version', { stdio: 'ignore' });
  } catch {
    issues.push({
      type: 'error',
      message: 'Docker is not installed or not accessible'
    });
  }
  
  // Check Docker Compose
  try {
    const { execSync } = require('child_process');
    execSync('docker compose version', { stdio: 'ignore' });
  } catch {
    try {
      const { execSync } = require('child_process');
      execSync('docker-compose --version', { stdio: 'ignore' });
    } catch {
      issues.push({
        type: 'error',
        message: 'Docker Compose is not installed'
      });
    }
  }
  
  // Check for existing containers that might conflict
  try {
    const { execSync } = require('child_process');
    const runningContainers = execSync('docker ps --format "{{.Names}}"', { encoding: 'utf-8' });
    const projectContainers = runningContainers.split('\n').filter(name => 
      name.includes('n8n-monitoring') || 
      name.includes('app-n8n') || 
      name.includes('stack-manager')
    );
    
    if (projectContainers.length > 0) {
      issues.push({
        type: 'warning',
        message: `Found existing containers: ${projectContainers.join(', ')}. These will be stopped during deployment.`
      });
    }
  } catch {
    // Ignore docker ps errors
  }
  
  return issues;
}

/**
 * Validate SSL/TLS configuration
 */
function validateSSLConfig(config) {
  const issues = [];
  
  if (config.sslProvider === 'cloudflare-tunnel' || config.sslProvider === 'cloudflare-api') {
    if (!config.cloudflareToken) {
      issues.push({
        type: 'error',
        field: 'cloudflareToken',
        message: 'Cloudflare API token is required for Cloudflare SSL'
      });
    }
    
    if (!config.cloudflareAccountId) {
      issues.push({
        type: 'error',
        field: 'cloudflareAccountId',
        message: 'Cloudflare Account ID is required'
      });
    }
    
    if (config.domain === 'localhost') {
      issues.push({
        type: 'error',
        field: 'domain',
        message: 'Cannot use localhost with Cloudflare SSL. Please use a real domain.'
      });
    }
  }
  
  if (config.sslProvider === 'nginx-proxy' && config.domain === 'localhost') {
    issues.push({
      type: 'warning',
      field: 'domain',
      message: 'Nginx Proxy Manager with localhost will only provide self-signed certificates'
    });
  }
  
  return issues;
}

/**
 * Main validation function
 */
async function validateDeploymentConfig(config) {
  const validation = {
    valid: true,
    errors: [],
    warnings: [],
    info: []
  };
  
  // Validate domain
  const domainValidation = await validateDomain(config.domain || 'localhost');
  validation.errors.push(...domainValidation.errors);
  validation.warnings.push(...domainValidation.warnings);
  
  // Check port conflicts
  const portConflicts = await checkPortConflicts(config);
  if (portConflicts.length > 0) {
    validation.errors.push(...portConflicts.map(c => c.message));
  }
  
  // Validate environment
  const envIssues = await validateEnvironment();
  envIssues.forEach(issue => {
    if (issue.type === 'error') {
      validation.errors.push(issue.message);
    } else {
      validation.warnings.push(issue.message);
    }
  });
  
  // Validate SSL config
  const sslIssues = validateSSLConfig(config);
  sslIssues.forEach(issue => {
    if (issue.type === 'error') {
      validation.errors.push(issue.message);
    } else {
      validation.warnings.push(issue.message);
    }
  });
  
  // Generate service URLs
  const serviceUrls = await validateServiceUrls(config);
  validation.info.push('Service URLs after deployment:');
  serviceUrls.forEach(s => {
    validation.info.push(`- ${s.service}: ${s.url}`);
  });
  
  // Set overall validity
  validation.valid = validation.errors.length === 0;
  
  return validation;
}

module.exports = {
  validateDomain,
  checkPortConflicts,
  validateServiceUrls,
  validateEnvironment,
  validateSSLConfig,
  validateDeploymentConfig
};