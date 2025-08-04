const dns = require('dns').promises;
const https = require('https');
const http = require('http');

/**
 * Real-time URL validation and DNS propagation checker
 */
class URLValidator {
    constructor() {
        this.validationCache = new Map();
        this.propagationCheckInterval = 5000; // 5 seconds
        this.maxPropagationAttempts = 60; // 5 minutes total
    }

    /**
     * Validate URL format and structure
     */
    validateURLFormat(url) {
        try {
            const urlObj = new URL(url.startsWith('http') ? url : `https://${url}`);
            
            // Check for localhost or local domains
            if (urlObj.hostname === 'localhost' || 
                urlObj.hostname === '127.0.0.1' ||
                urlObj.hostname.endsWith('.local') ||
                urlObj.hostname.endsWith('.localhost')) {
                return { valid: true, isLocal: true, hostname: urlObj.hostname };
            }

            // Validate domain format
            const domainRegex = /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/i;
            if (!domainRegex.test(urlObj.hostname)) {
                return { valid: false, error: 'Invalid domain format' };
            }

            return { valid: true, isLocal: false, hostname: urlObj.hostname };
        } catch (error) {
            return { valid: false, error: 'Invalid URL format' };
        }
    }

    /**
     * Check DNS resolution for a domain
     */
    async checkDNSResolution(hostname) {
        try {
            const addresses = await dns.resolve4(hostname);
            return { 
                resolved: true, 
                addresses,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            if (error.code === 'ENOTFOUND') {
                return { resolved: false, error: 'Domain not found' };
            }
            return { resolved: false, error: error.message };
        }
    }

    /**
     * Check if domain points to current server
     */
    async checkDomainPointsToServer(hostname, serverIPs = []) {
        try {
            const resolution = await this.checkDNSResolution(hostname);
            if (!resolution.resolved) {
                return { pointsToServer: false, ...resolution };
            }

            // Get server's public IPs if not provided
            if (serverIPs.length === 0) {
                serverIPs = await this.getServerPublicIPs();
            }

            const pointsToServer = resolution.addresses.some(addr => 
                serverIPs.includes(addr)
            );

            return {
                pointsToServer,
                domainIPs: resolution.addresses,
                serverIPs,
                timestamp: resolution.timestamp
            };
        } catch (error) {
            return { pointsToServer: false, error: error.message };
        }
    }

    /**
     * Get server's public IP addresses
     */
    async getServerPublicIPs() {
        const ips = [];
        
        try {
            // Try multiple IP detection services
            const services = [
                'https://api.ipify.org?format=json',
                'https://ifconfig.me/ip',
                'https://icanhazip.com'
            ];

            for (const service of services) {
                try {
                    const response = await this.httpGet(service);
                    const ip = response.ip || response.trim();
                    if (ip && !ips.includes(ip)) {
                        ips.push(ip);
                    }
                    break; // Use first successful service
                } catch (err) {
                    continue;
                }
            }
        } catch (error) {
            console.error('Failed to get public IP:', error);
        }

        return ips;
    }

    /**
     * Simple HTTP GET request
     */
    httpGet(url) {
        return new Promise((resolve, reject) => {
            const client = url.startsWith('https') ? https : http;
            
            client.get(url, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    try {
                        resolve(JSON.parse(data));
                    } catch {
                        resolve(data);
                    }
                });
            }).on('error', reject);
        });
    }

    /**
     * Monitor DNS propagation
     */
    async monitorPropagation(hostname, targetIPs, callback) {
        let attempts = 0;
        const checkId = `${hostname}-${Date.now()}`;
        
        const checkPropagation = async () => {
            attempts++;
            
            try {
                const result = await this.checkDomainPointsToServer(hostname, targetIPs);
                
                const status = {
                    hostname,
                    attempt: attempts,
                    maxAttempts: this.maxPropagationAttempts,
                    ...result
                };

                callback(status);

                if (result.pointsToServer || attempts >= this.maxPropagationAttempts) {
                    // Propagation complete or timed out
                    return status;
                }

                // Continue checking
                await new Promise(resolve => setTimeout(resolve, this.propagationCheckInterval));
                return checkPropagation();
            } catch (error) {
                callback({ 
                    hostname, 
                    attempt: attempts,
                    error: error.message 
                });
                return { error: error.message };
            }
        };

        return checkPropagation();
    }

    /**
     * Validate URL with real-time feedback
     */
    async validateURL(url, options = {}) {
        const validation = {
            url,
            timestamp: new Date().toISOString(),
            checks: {}
        };

        // Step 1: Validate format
        const format = this.validateURLFormat(url);
        validation.checks.format = format;
        
        if (!format.valid) {
            validation.valid = false;
            validation.error = format.error;
            return validation;
        }

        // Step 2: Check if local domain (skip DNS for local)
        if (format.isLocal) {
            validation.valid = true;
            validation.isLocal = true;
            validation.checks.dns = { resolved: true, isLocal: true };
            return validation;
        }

        // Step 3: Check DNS resolution
        const dns = await this.checkDNSResolution(format.hostname);
        validation.checks.dns = dns;

        if (!dns.resolved && !options.allowUnresolved) {
            validation.valid = false;
            validation.error = 'Domain does not resolve';
            return validation;
        }

        // Step 4: Check if points to server (if required)
        if (options.checkPointsToServer) {
            const pointing = await this.checkDomainPointsToServer(
                format.hostname, 
                options.serverIPs
            );
            validation.checks.pointing = pointing;
            
            if (!pointing.pointsToServer && !options.allowExternal) {
                validation.valid = false;
                validation.error = 'Domain does not point to this server';
                return validation;
            }
        }

        validation.valid = true;
        return validation;
    }

    /**
     * Generate subdomain suggestions
     */
    generateSubdomainSuggestions(baseDomain, services) {
        const suggestions = {};
        
        const defaultSubdomains = {
            stackManager: 'stack',
            grafana: 'grafana',
            n8n: 'n8n',
            prometheus: 'metrics'
        };

        for (const [service, defaultSub] of Object.entries(defaultSubdomains)) {
            suggestions[service] = `${defaultSub}.${baseDomain}`;
        }

        return suggestions;
    }

    /**
     * Batch validate multiple URLs
     */
    async validateServiceURLs(urls, options = {}) {
        const results = {};
        
        for (const [service, url] of Object.entries(urls)) {
            results[service] = await this.validateURL(url, options);
        }

        return {
            allValid: Object.values(results).every(r => r.valid),
            results,
            timestamp: new Date().toISOString()
        };
    }
}

module.exports = URLValidator;