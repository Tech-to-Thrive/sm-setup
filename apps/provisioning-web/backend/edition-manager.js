/**
 * Edition-based feature management
 */
class EditionManager {
    constructor() {
        this.editions = {
            community: {
                name: 'Community Edition',
                features: {
                    sslProviders: ['none', 'npm'], // Development or Nginx Proxy Manager
                    maxDomains: 1,
                    subdomains: false,
                    customPorts: false,
                    advancedMonitoring: false,
                    multiTenant: false,
                    backupEncryption: false,
                    automatedBackups: false,
                    cloudflareIntegration: false,
                    customBranding: false,
                    apiAccess: false,
                    prioritySupport: false,
                    sla: false,
                    analytics: 'basic',
                    userLimit: 5,
                    workflowLimit: 50,
                    retentionDays: 7
                },
                support: {
                    url: 'https://www.skool.com/ai-stack-masters',
                    type: 'community'
                }
            },
            pro: {
                name: 'Pro Edition',
                features: {
                    sslProviders: ['none', 'npm', 'cloudflare-tunnel', 'cloudflare-api'],
                    maxDomains: 5,
                    subdomains: true,
                    customPorts: true,
                    advancedMonitoring: true,
                    multiTenant: true,
                    backupEncryption: true,
                    automatedBackups: true,
                    cloudflareIntegration: true,
                    customBranding: true,
                    apiAccess: true,
                    prioritySupport: true,
                    sla: false,
                    analytics: 'advanced',
                    userLimit: 50,
                    workflowLimit: 500,
                    retentionDays: 30,
                    // Pro-specific features
                    workflowTemplates: true,
                    customExporters: true,
                    webhookIntegration: true,
                    slackIntegration: true,
                    emailAlerts: true,
                    customDashboards: true,
                    roleBasedAccess: true
                },
                support: {
                    url: 'https://www.skool.com/ai-stack-master-pros',
                    type: 'priority',
                    responseTime: '24h'
                }
            },
            enterprise: {
                name: 'Enterprise Edition',
                features: {
                    sslProviders: ['none', 'npm', 'cloudflare-tunnel', 'cloudflare-api', 'custom'],
                    maxDomains: -1, // Unlimited
                    subdomains: true,
                    customPorts: true,
                    advancedMonitoring: true,
                    multiTenant: true,
                    backupEncryption: true,
                    automatedBackups: true,
                    cloudflareIntegration: true,
                    customBranding: true,
                    apiAccess: true,
                    prioritySupport: true,
                    sla: true,
                    analytics: 'enterprise',
                    userLimit: -1, // Unlimited
                    workflowLimit: -1, // Unlimited
                    retentionDays: 365,
                    // All Pro features plus:
                    workflowTemplates: true,
                    customExporters: true,
                    webhookIntegration: true,
                    slackIntegration: true,
                    emailAlerts: true,
                    customDashboards: true,
                    roleBasedAccess: true,
                    // Enterprise-specific
                    ssoIntegration: true,
                    ldapIntegration: true,
                    auditLogs: true,
                    complianceReports: true,
                    customMetrics: true,
                    dedicatedSupport: true,
                    onPremiseOption: true,
                    whiteLabeling: true,
                    customIntegrations: true,
                    dataResidency: true,
                    disasterRecovery: true,
                    highAvailability: true,
                    loadBalancing: true,
                    geoReplication: true
                },
                support: {
                    url: 'https://www.skool.com/ai-stack-master-pros',
                    type: 'dedicated',
                    responseTime: '1h',
                    sla: '99.9%',
                    account_manager: true
                }
            }
        };

        // Feature descriptions for UI
        this.featureDescriptions = {
            sslProviders: 'Available SSL/TLS certificate providers',
            maxDomains: 'Maximum number of domains supported',
            subdomains: 'Support for subdomain configuration',
            customPorts: 'Ability to customize service ports',
            advancedMonitoring: 'Advanced metrics and monitoring features',
            multiTenant: 'Support for multiple isolated tenants',
            backupEncryption: 'Encrypted backup storage',
            automatedBackups: 'Scheduled automatic backups',
            cloudflareIntegration: 'Full Cloudflare API and Tunnel support',
            customBranding: 'White-label and custom branding options',
            apiAccess: 'Full API access for automation',
            prioritySupport: 'Priority technical support',
            sla: 'Service Level Agreement guarantee',
            analytics: 'Analytics and reporting capabilities',
            userLimit: 'Maximum number of users',
            workflowLimit: 'Maximum number of workflows',
            retentionDays: 'Data retention period in days',
            workflowTemplates: 'Pre-built workflow templates',
            customExporters: 'Create custom Prometheus exporters',
            webhookIntegration: 'Webhook notifications',
            slackIntegration: 'Slack notifications and alerts',
            emailAlerts: 'Email alert system',
            customDashboards: 'Create custom Grafana dashboards',
            roleBasedAccess: 'Role-based access control',
            ssoIntegration: 'Single Sign-On support',
            ldapIntegration: 'LDAP/Active Directory integration',
            auditLogs: 'Comprehensive audit logging',
            complianceReports: 'Compliance and security reports',
            customMetrics: 'Define custom metrics',
            dedicatedSupport: 'Dedicated support team',
            onPremiseOption: 'On-premise deployment option',
            whiteLabeling: 'Complete white-label solution',
            customIntegrations: 'Custom third-party integrations',
            dataResidency: 'Choose data storage location',
            disasterRecovery: 'Disaster recovery planning',
            highAvailability: 'High availability configuration',
            loadBalancing: 'Load balancing support',
            geoReplication: 'Geographic replication'
        };
    }

    /**
     * Get edition features
     */
    getEdition(editionName) {
        return this.editions[editionName] || this.editions.community;
    }

    /**
     * Check if feature is available in edition
     */
    hasFeature(edition, feature) {
        const editionData = this.getEdition(edition);
        return editionData.features[feature] === true || 
               (Array.isArray(editionData.features[feature]) && editionData.features[feature].length > 0) ||
               (typeof editionData.features[feature] === 'number' && editionData.features[feature] !== 0);
    }

    /**
     * Get available SSL providers for edition
     */
    getAvailableSSLProviders(edition) {
        const editionData = this.getEdition(edition);
        return editionData.features.sslProviders || ['none'];
    }

    /**
     * Validate configuration against edition limits
     */
    validateConfigForEdition(config, edition) {
        const editionData = this.getEdition(edition);
        const validation = {
            valid: true,
            errors: [],
            warnings: []
        };

        // Check SSL provider
        if (config.sslProvider && !editionData.features.sslProviders.includes(config.sslProvider)) {
            validation.valid = false;
            validation.errors.push(`SSL provider '${config.sslProvider}' not available in ${editionData.name}`);
        }

        // Check domain limits
        if (config.domains && editionData.features.maxDomains !== -1) {
            if (config.domains.length > editionData.features.maxDomains) {
                validation.valid = false;
                validation.errors.push(`Maximum ${editionData.features.maxDomains} domain(s) allowed in ${editionData.name}`);
            }
        }

        // Check subdomain support
        if (config.useSubdomains && !editionData.features.subdomains) {
            validation.valid = false;
            validation.errors.push(`Subdomain configuration not available in ${editionData.name}`);
        }

        // Check custom ports
        if (config.customPorts && !editionData.features.customPorts) {
            validation.valid = false;
            validation.errors.push(`Custom port configuration not available in ${editionData.name}`);
        }

        // Check user limit
        if (config.estimatedUsers && editionData.features.userLimit !== -1) {
            if (config.estimatedUsers > editionData.features.userLimit) {
                validation.warnings.push(`User limit (${editionData.features.userLimit}) may be exceeded in ${editionData.name}`);
            }
        }

        return validation;
    }

    /**
     * Get edition comparison data for UI
     */
    getEditionComparison() {
        const comparison = [];
        const allFeatures = Object.keys(this.featureDescriptions);

        for (const feature of allFeatures) {
            const row = {
                feature: feature,
                description: this.featureDescriptions[feature],
                editions: {}
            };

            for (const [editionName, editionData] of Object.entries(this.editions)) {
                const value = editionData.features[feature];
                if (value === true) {
                    row.editions[editionName] = '✓';
                } else if (value === false || value === undefined) {
                    row.editions[editionName] = '✗';
                } else if (value === -1) {
                    row.editions[editionName] = 'Unlimited';
                } else if (Array.isArray(value)) {
                    row.editions[editionName] = value.join(', ');
                } else {
                    row.editions[editionName] = value;
                }
            }

            comparison.push(row);
        }

        return comparison;
    }

    /**
     * Get recommended edition based on requirements
     */
    recommendEdition(requirements) {
        // Start with community and upgrade as needed
        let recommendedEdition = 'community';

        // Check domain requirements
        if (requirements.domains > 1 || requirements.subdomains) {
            recommendedEdition = 'pro';
        }

        // Check SSL requirements
        if (requirements.sslProvider && 
            ['cloudflare-tunnel', 'cloudflare-api'].includes(requirements.sslProvider)) {
            recommendedEdition = 'pro';
        }

        // Check user/workflow limits
        if (requirements.estimatedUsers > 50 || requirements.estimatedWorkflows > 500) {
            recommendedEdition = 'enterprise';
        }

        // Check enterprise features
        const enterpriseFeatures = [
            'ssoIntegration', 'ldapIntegration', 'highAvailability', 
            'whiteLabeling', 'onPremiseOption', 'dataResidency'
        ];

        for (const feature of enterpriseFeatures) {
            if (requirements[feature]) {
                recommendedEdition = 'enterprise';
                break;
            }
        }

        return {
            edition: recommendedEdition,
            reasoning: this.getRecommendationReasoning(requirements, recommendedEdition)
        };
    }

    /**
     * Get reasoning for edition recommendation
     */
    getRecommendationReasoning(requirements, edition) {
        const reasons = [];

        if (edition === 'pro') {
            if (requirements.domains > 1) {
                reasons.push('Multiple domains required');
            }
            if (requirements.subdomains) {
                reasons.push('Subdomain support needed');
            }
            if (requirements.cloudflareIntegration) {
                reasons.push('Cloudflare integration requested');
            }
            if (requirements.advancedMonitoring) {
                reasons.push('Advanced monitoring features needed');
            }
        }

        if (edition === 'enterprise') {
            if (requirements.estimatedUsers > 50) {
                reasons.push('Large user base (>50 users)');
            }
            if (requirements.estimatedWorkflows > 500) {
                reasons.push('High workflow volume (>500)');
            }
            if (requirements.ssoIntegration) {
                reasons.push('SSO integration required');
            }
            if (requirements.highAvailability) {
                reasons.push('High availability configuration needed');
            }
            if (requirements.onPremiseOption) {
                reasons.push('On-premise deployment required');
            }
        }

        return reasons;
    }

    /**
     * Generate configuration based on edition
     */
    generateEditionConfig(edition, baseConfig) {
        const editionData = this.getEdition(edition);
        const config = { ...baseConfig };

        // Apply edition-specific defaults
        config.edition = edition;
        config.features = { ...editionData.features };

        // Set retention based on edition
        config.prometheusRetention = `${editionData.features.retentionDays}d`;
        config.lokiRetention = `${Math.min(editionData.features.retentionDays, 30)}d`;

        // Set resource limits based on edition
        if (edition === 'community') {
            config.resourceLimits = {
                n8n: '1g',
                postgres: '1g',
                redis: '512m',
                grafana: '512m',
                prometheus: '1g'
            };
        } else if (edition === 'pro') {
            config.resourceLimits = {
                n8n: '2g',
                postgres: '2g',
                redis: '1g',
                grafana: '1g',
                prometheus: '2g'
            };
        } else if (edition === 'enterprise') {
            config.resourceLimits = {
                n8n: '4g',
                postgres: '4g',
                redis: '2g',
                grafana: '2g',
                prometheus: '4g'
            };
        }

        return config;
    }
}

module.exports = EditionManager;