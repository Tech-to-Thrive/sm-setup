const crypto = require('crypto');

class LogAnonymizer {
  constructor() {
    // Patterns to detect and anonymize sensitive data
    this.patterns = {
      // Email addresses
      email: /([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g,
      // IP addresses (IPv4)
      ipv4: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/g,
      // Domains (but preserve localhost)
      domain: /(?<![@/])([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.)+[a-zA-Z]{2,}/g,
      // API keys and tokens (common patterns)
      apiKey: /(?:api[_-]?key|token|secret|password|pwd|pass)["\s]*[:=]["\s]*["']?([^"'\s,;}]+)["']?/gi,
      // UUIDs
      uuid: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
      // File paths with usernames
      userPath: /\/(?:home|users?)\/([^/\s]+)/gi,
      // Docker image names with private registries
      dockerRegistry: /(?:^|\s)([a-zA-Z0-9.-]+(?::[0-9]+)?\/[^\s]+)/g,
      // Passwords in various formats
      password: /(?:password|passwd|pwd|pass)\s*[:=]\s*["']?([^"'\s,;}]+)["']?/gi,
      // Webhook URLs
      webhook: /(https?:\/\/[^\s]+webhook[^\s]*)/gi,
      // JWT tokens
      jwt: /eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g
    };

    // Whitelist of values to not anonymize
    this.whitelist = new Set([
      'localhost',
      '127.0.0.1',
      '0.0.0.0',
      'example.com',
      'test.com',
      'docker.io',
      'github.com',
      'npmjs.org',
      'ubuntu.com'
    ]);
  }

  /**
   * Generate consistent anonymous replacement for a value
   */
  generateAnonymousValue(value, type) {
    // Use SHA256 to generate consistent replacements
    const hash = crypto.createHash('sha256').update(value).digest('hex');
    const shortHash = hash.substring(0, 8);

    switch (type) {
      case 'email':
        const [localPart, domain] = value.split('@');
        return `user_${shortHash}@example.com`;
      
      case 'ipv4':
        // Keep private IP ranges identifiable
        if (value.startsWith('192.168.') || value.startsWith('10.') || value.startsWith('172.')) {
          return value.replace(/\d+$/, 'XXX');
        }
        return `XXX.XXX.XXX.XXX`;
      
      case 'domain':
        if (this.whitelist.has(value)) return value;
        return `domain-${shortHash}.example.com`;
      
      case 'apiKey':
      case 'password':
      case 'jwt':
        return `[REDACTED-${type.toUpperCase()}]`;
      
      case 'uuid':
        return `xxxxxxxx-xxxx-xxxx-xxxx-${shortHash}0000`;
      
      case 'userPath':
        return `/home/user_${shortHash}`;
      
      case 'dockerRegistry':
        return `registry.example.com/${shortHash}`;
      
      case 'webhook':
        return `https://webhook.example.com/${shortHash}`;
      
      default:
        return `[ANONYMIZED-${shortHash}]`;
    }
  }

  /**
   * Anonymize a single log line
   */
  anonymizeLine(line) {
    let anonymized = line;

    // Apply each pattern
    for (const [type, pattern] of Object.entries(this.patterns)) {
      anonymized = anonymized.replace(pattern, (match, ...groups) => {
        // For patterns with capture groups
        if (groups.length > 0 && groups[0]) {
          const capturedValue = groups[0];
          
          // Skip if whitelisted
          if (this.whitelist.has(capturedValue)) {
            return match;
          }

          // Special handling for different types
          if (type === 'email') {
            return this.generateAnonymousValue(match, type);
          } else if (type === 'userPath') {
            const username = groups[0];
            return match.replace(username, `user_${this.generateAnonymousValue(username, type).substring(0, 8)}`);
          } else if (type === 'apiKey' || type === 'password') {
            // Replace the value part but keep the key part
            const keyPart = match.substring(0, match.indexOf(capturedValue));
            return keyPart + this.generateAnonymousValue(capturedValue, type);
          }
        }

        return this.generateAnonymousValue(match, type);
      });
    }

    return anonymized;
  }

  /**
   * Anonymize an entire log
   */
  anonymizeLog(log) {
    if (typeof log === 'string') {
      return log.split('\n').map(line => this.anonymizeLine(line)).join('\n');
    } else if (Array.isArray(log)) {
      return log.map(entry => this.anonymizeLogEntry(entry));
    } else if (typeof log === 'object') {
      return this.anonymizeObject(log);
    }
    return log;
  }

  /**
   * Anonymize a log entry object
   */
  anonymizeLogEntry(entry) {
    if (typeof entry === 'string') {
      return this.anonymizeLine(entry);
    } else if (typeof entry === 'object' && entry !== null) {
      const anonymized = {};
      for (const [key, value] of Object.entries(entry)) {
        if (typeof value === 'string') {
          anonymized[key] = this.anonymizeLine(value);
        } else if (typeof value === 'object') {
          anonymized[key] = this.anonymizeObject(value);
        } else {
          anonymized[key] = value;
        }
      }
      return anonymized;
    }
    return entry;
  }

  /**
   * Anonymize a configuration object
   */
  anonymizeObject(obj) {
    if (!obj || typeof obj !== 'object') return obj;
    
    const anonymized = Array.isArray(obj) ? [] : {};
    
    for (const [key, value] of Object.entries(obj)) {
      // Keys that should be fully redacted
      const sensitiveKeys = ['password', 'secret', 'token', 'apiKey', 'privateKey', 'credentials'];
      if (sensitiveKeys.some(k => key.toLowerCase().includes(k.toLowerCase()))) {
        anonymized[key] = '[REDACTED]';
        continue;
      }

      // Recursively anonymize nested objects
      if (typeof value === 'object' && value !== null) {
        anonymized[key] = this.anonymizeObject(value);
      } else if (typeof value === 'string') {
        anonymized[key] = this.anonymizeLine(value);
      } else {
        anonymized[key] = value;
      }
    }

    return anonymized;
  }

  /**
   * Generate deployment report with anonymized data
   */
  generateAnonymizedReport(deploymentData) {
    const report = {
      timestamp: new Date().toISOString(),
      deploymentId: deploymentData.id || 'unknown',
      status: deploymentData.status,
      duration: deploymentData.duration || null,
      
      // System information (anonymized)
      system: {
        platform: process.platform,
        arch: process.arch,
        nodeVersion: process.version,
        memory: {
          total: Math.round(require('os').totalmem() / 1024 / 1024 / 1024) + 'GB',
          free: Math.round(require('os').freemem() / 1024 / 1024 / 1024) + 'GB'
        },
        cpus: require('os').cpus().length
      },

      // Configuration (anonymized)
      config: this.anonymizeObject(deploymentData.config || {}),

      // Steps with anonymized logs
      steps: (deploymentData.steps || []).map(step => ({
        id: step.id,
        name: step.name,
        status: step.status,
        duration: step.duration,
        error: step.error ? this.anonymizeLine(step.error.message || step.error) : null,
        logs: (step.logs || []).map(log => this.anonymizeLogEntry(log))
      })),

      // Resources used
      resources: deploymentData.resources || {},

      // Errors (anonymized)
      errors: (deploymentData.errors || []).map(err => this.anonymizeLine(err)),

      // Package versions (safe to include)
      packages: deploymentData.packages || {},

      // Docker images used (registry URLs anonymized)
      dockerImages: (deploymentData.dockerImages || []).map(img => this.anonymizeLine(img))
    };

    return report;
  }
}

module.exports = LogAnonymizer;