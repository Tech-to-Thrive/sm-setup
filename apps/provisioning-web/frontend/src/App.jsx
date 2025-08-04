import { useState, useEffect, useRef } from 'react'
import aiStackMastersLogo from './assets/ai-stack-masters-logo.png'
import { deploymentAPI, validationAPI, exportAPI, dnsAPI, snapshotAPI, telemetryAPI } from './api/backend'
import { useBackendIntegration } from './hooks/useBackendIntegration'
import { validateEmail, validateDomain, validatePassword, getValidationClass } from './utils/validators'
import './App.css'

// Debug validators
console.log('[App] Validators imported:', { validateEmail, validateDomain, validatePassword, getValidationClass });

function App() {
  // Add debugging
  console.log('[App] Component rendering...');
  
  const [currentStep, setCurrentStep] = useState(1)
  const [edition, setEdition] = useState('community')
  const [theme, setTheme] = useState('dark')
  const [expertMode, setExpertMode] = useState(false)
  const [config, setConfig] = useState({
    adminEmail: '',
    adminPassword: '',
    domain: '',
    sslProvider: 'none',
    stackManagerUrl: '',
    n8nUrl: '',
    grafanaUrl: '',
    useCustomPasswords: false,
    enableMfa: false,
    enableAudit: true,
    enableBackups: true,
    skipDnsValidation: false
  })
  const [validationErrors, setValidationErrors] = useState({})
  const [deploymentStatus, setDeploymentStatus] = useState('idle') // idle, deploying, completed, failed
  const [deploymentLogs, setDeploymentLogs] = useState([])
  const [urlValidation, setUrlValidation] = useState({})
  const [dnsStatus, setDnsStatus] = useState({})
  const [checkingDns, setCheckingDns] = useState(false)
  const [preflightStatus, setPreflightStatus] = useState(null)
  const [checkingPreflight, setCheckingPreflight] = useState(false)
  const [snapshots, setSnapshots] = useState([])
  const [showRollbackModal, setShowRollbackModal] = useState(false)
  const [rollbackInProgress, setRollbackInProgress] = useState(false)
  const [currentDeploymentId, setCurrentDeploymentId] = useState(null)
  const [telemetryStatus, setTelemetryStatus] = useState(null)
  
  // Use backend integration hook
  const { 
    validateDomain: validateDomainAPI,
    validateServiceUrl,
    checkDnsPropagation,
    validating 
  } = useBackendIntegration()

  // Domain validation state
  const [isDomainValid, setIsDomainValid] = useState(false);
  const [isDomainValidating, setIsDomainValidating] = useState(false);
  const domainValidationTimer = useRef(null);

  // Domain validation with debouncing
  const validateDomainWithDebounce = (domain) => {
    // Clear any existing timer
    if (domainValidationTimer.current) {
      clearTimeout(domainValidationTimer.current);
    }

    // Skip DNS validation if enabled in expert mode
    if (expertMode && config.skipDnsValidation) {
      setIsDomainValid(true);
      setIsDomainValidating(false);
      return;
    }

    // Only validate if domain looks complete (ends with .something)
    const domainPattern = /\.[a-z]+$/i;
    if (domain && domain.match(domainPattern)) {
      setIsDomainValidating(true);
      
      // Set a new timer
      domainValidationTimer.current = setTimeout(async () => {
        try {
          const validation = await validateDomainAPI(domain);
          if (!validation.valid) {
            setValidationErrors(prev => ({ ...prev, domain: validation.message }));
            setIsDomainValid(false);
          } else {
            setValidationErrors(prev => ({ ...prev, domain: null }));
            setIsDomainValid(true);
          }
        } catch (error) {
          console.error('Domain validation error:', error);
        } finally {
          setIsDomainValidating(false);
        }
      }, 1000); // 1 second delay
    } else {
      setIsDomainValid(false);
      setIsDomainValidating(false);
    }
  };

  // Cleanup timer on unmount
  useEffect(() => {
    return () => {
      if (domainValidationTimer.current) {
        clearTimeout(domainValidationTimer.current);
      }
    };
  }, []);

  // Update service URLs when domain changes
  useEffect(() => {
    if (config.domain) {
      const isLocalhost = config.domain === 'localhost'
      setConfig(prev => ({
        ...prev,
        stackManagerUrl: isLocalhost ? 'localhost:3001' : `stack.${config.domain}`,
        n8nUrl: isLocalhost ? 'localhost:5678' : `n8n.${config.domain}`,
        grafanaUrl: isLocalhost ? 'localhost:3000' : `grafana.${config.domain}`
      }))
    }
  }, [config.domain])

  const handleInputChange = async (field, value) => {
    console.log('[handleInputChange] Field:', field, 'Value:', value);
    
    try {
      setConfig(prev => ({ ...prev, [field]: value }))
      
      // Clear validation error when user starts typing
      if (validationErrors[field]) {
        setValidationErrors(prev => ({ ...prev, [field]: null }))
      }
    
    // Real-time password validation
    if (field === 'adminPassword' && value) {
      const passwordResult = validatePassword(value, false)
      if (!passwordResult.valid) {
        setValidationErrors(prev => ({ 
          ...prev, 
          adminPassword: passwordResult.message
        }))
      }
    }
    
    // Domain validation with debouncing
    if (field === 'domain') {
      validateDomainWithDebounce(value);
    }
    
      // Real-time URL validation
      if (['stackManagerUrl', 'n8nUrl', 'grafanaUrl'].includes(field) && value) {
        const validation = await validateServiceUrl(value, field.replace('Url', ''), edition, config.sslProvider)
        setUrlValidation(prev => ({ 
          ...prev, 
          [field]: validation 
        }))
        if (!validation.valid) {
          setValidationErrors(prev => ({ ...prev, [field]: validation.message }))
        }
      }
    } catch (error) {
      console.error('[handleInputChange] Error:', error);
      console.error('[handleInputChange] Stack:', error.stack);
    }
  }

  const validateStep = (step) => {
    const errors = {}
    
    if (step === 1) {
      if (!config.adminEmail) {
        errors.adminEmail = 'Admin email is required'
      } else {
        const emailResult = validateEmail(config.adminEmail)
        if (!emailResult.valid) {
          errors.adminEmail = emailResult.message
        }
      }
      
      if (!config.domain) {
        errors.domain = 'Domain is required'
      } else {
        console.log('[validateStep] Calling validateDomain with:', config.domain);
        console.log('[validateStep] validateDomain function:', validateDomain);
        try {
          const domainResult = validateDomain(config.domain, expertMode)
          console.log('[validateStep] Domain validation result:', domainResult);
          if (!domainResult.valid) {
            errors.domain = domainResult.message
          }
        } catch (error) {
          console.error('[validateStep] Error calling validateDomain:', error);
          errors.domain = 'Domain validation error'
        }
      }
    }
    
    setValidationErrors(errors)
    return Object.keys(errors).length === 0
  }

  const nextStep = () => {
    if (validateStep(currentStep)) {
      setCurrentStep(prev => Math.min(prev + 1, 5))
    }
  }

  const prevStep = () => {
    setCurrentStep(prev => Math.max(prev - 1, 1))
  }

  const runPreflightChecks = async () => {
    setCheckingPreflight(true)
    setPreflightStatus(null)
    
    try {
      const response = await fetch('/api/preflight', {
        credentials: 'include'
      })
      const data = await response.json()
      setPreflightStatus(data)
      
      // If critical issues, prevent deployment
      if (!data.passed && data.summary.criticalIssues.length > 0) {
        return false
      }
      return true
    } catch (error) {
      console.error('Pre-flight check failed:', error)
      setPreflightStatus({
        passed: false,
        error: error.message,
        summary: {
          criticalIssues: ['Failed to run pre-flight checks'],
          warnings: [],
          message: `Pre-flight checks failed: ${error.message}`
        }
      })
      return false
    } finally {
      setCheckingPreflight(false)
    }
  }

  const loadSnapshots = async (deploymentId) => {
    try {
      const data = await snapshotAPI.list(deploymentId)
      setSnapshots(data.snapshots || [])
    } catch (error) {
      console.error('Failed to load snapshots:', error)
      setSnapshots([])
    }
  }

  const performRollback = async (snapshotId) => {
    setRollbackInProgress(true)
    try {
      const result = await snapshotAPI.rollback(currentDeploymentId, snapshotId)
      if (result.success) {
        setDeploymentStatus('rolled-back')
        setDeploymentLogs(prev => [...prev, {
          type: 'success',
          message: `Successfully rolled back to ${result.snapshot.step ? `step ${result.snapshot.step}` : 'previous state'}`
        }])
        setShowRollbackModal(false)
      } else {
        setDeploymentLogs(prev => [...prev, {
          type: 'error',
          message: `Rollback failed: ${result.message}`
        }])
      }
    } catch (error) {
      console.error('Rollback failed:', error)
      setDeploymentLogs(prev => [...prev, {
        type: 'error',
        message: `Rollback error: ${error.message}`
      }])
    } finally {
      setRollbackInProgress(false)
    }
  }

  const startDeployment = async () => {
    // Run pre-flight checks first
    const preflightPassed = await runPreflightChecks()
    if (!preflightPassed) {
      // Don't proceed with deployment if critical issues
      return
    }
    
    setCurrentStep(5)
    setDeploymentStatus('deploying')
    setDeploymentLogs([])
    
    try {
      // Start deployment using backend API
      const deploymentConfig = {
        ...config,
        edition,
        // Add any additional config needed for deployment
        adminPassword: config.adminPassword || generateSecurePassword(),
        postgresPassword: generateSecurePassword(),
        redisPassword: generateSecurePassword(),
        jwtSecret: generateSecureToken(),
        anonKey: generateSecureToken(),
        serviceKey: generateSecureToken()
      }
      
      const result = await deploymentAPI.start(deploymentConfig)
      
      if (result.deploymentId) {
        setCurrentDeploymentId(result.deploymentId)
        
        // Connect WebSocket for real-time logs
        const ws = deploymentAPI.connectWebSocket()
        
        ws.onmessage = (event) => {
          const data = JSON.parse(event.data)
          if (data.type === 'log') {
            setDeploymentLogs(prev => [...prev, data.message])
          } else if (data.type === 'status') {
            setDeploymentStatus(data.status)
            // Load snapshots when deployment fails
            if (data.status === 'failed' && result.deploymentId) {
              loadSnapshots(result.deploymentId)
            }
            // Fetch telemetry status on completion
            if (data.status === 'completed' && result.deploymentId) {
              fetchTelemetryStatus(result.deploymentId)
            }
          }
        }
        
        ws.onerror = (error) => {
          console.error('WebSocket error:', error)
          setDeploymentStatus('failed')
          // Load snapshots on error
          if (result.deploymentId) {
            loadSnapshots(result.deploymentId)
          }
        }
        
        ws.onclose = () => {
          console.log('WebSocket closed')
        }
      }
    } catch (error) {
      console.error('Deployment failed:', error)
      setDeploymentStatus('failed')
      setDeploymentLogs(prev => [...prev, `Error: ${error.message}`])
    }
  }
  
  // Helper functions for generating secure passwords/tokens
  const generateSecurePassword = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*'
    let password = ''
    for (let i = 0; i < 16; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return password
  }
  
  const generateSecureToken = () => {
    return Array.from(crypto.getRandomValues(new Uint8Array(32)))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')
  }

  const exportLogs = () => {
    const logsText = deploymentLogs.join('\n')
    const blob = new Blob([logsText], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'deployment-logs.txt'
    a.click()
    URL.revokeObjectURL(url)
  }

  const exportConfig = () => {
    const configText = JSON.stringify(config, null, 2)
    const blob = new Blob([configText], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'deployment-config.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const downloadDeploymentLogs = async (type = 'full') => {
    if (!currentDeploymentId) {
      alert('No deployment to download logs for')
      return
    }
    
    try {
      await exportAPI.downloadLogs(currentDeploymentId, type)
    } catch (error) {
      console.error('Failed to download logs:', error)
      alert('Failed to download logs. Please try again.')
    }
  }

  const fetchTelemetryStatus = async (deploymentId) => {
    try {
      const status = await telemetryAPI.getStatus(deploymentId)
      setTelemetryStatus(status)
    } catch (error) {
      console.error('Failed to fetch telemetry status:', error)
    }
  }

  return (
    <div className={`app-container ${theme}`} data-theme={theme} data-edition={edition}>
      {/* Edition Demo Area (Hidden hover trigger) */}
      <div className="edition-hover-area"></div>
      <div 
        className="edition-demo-toggle" 
        id="editionDemoToggle"
        onClick={() => setEdition(edition === 'community' ? 'pro' : 'community')}
        style={{ cursor: 'pointer' }}
      >
        🎭 Demo: <span id="demoEditionText">{edition === 'community' ? 'Community' : 'Pro'}</span>
      </div>
      
      {/* Theme Toggle */}
      <button className="theme-toggle" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')} aria-label="Toggle theme">
        <span className="theme-icon" id="themeIcon">{theme === 'dark' ? '🌙' : '☀️'}</span>
      </button>

      <div className="container">
        {/* Header - Legacy Style */}
        <header className="header">
          <div className="logo-container">
            <img 
              src={aiStackMastersLogo} 
              alt="AI Stack Masters - Logo with text" 
              className="logo-img" 
              title="AI Stack Masters"
            />
          </div>
          <h2 className="subtitle">Stack Builder</h2>
        </header>

        {/* Progress Bar */}
        <div className="progress-container">
          <div className="progress-bar">
            <div 
              className="progress-line" 
              style={{ 
                width: currentStep === 1 ? '0' : `calc(${((currentStep - 1) / 4) * 100}% - 25px)` 
              }}
            ></div>
            {[1, 2, 3, 4, 5].map(step => (
              <div 
                key={step} 
                className={`progress-step ${currentStep >= step ? 'active' : ''}`} 
                data-step={step}
                onClick={() => setCurrentStep(step)}
              >
                <div className="progress-step-circle">{step}</div>
                <div className="progress-step-label">
                  {step === 1 ? 'Basic Info' : 
                   step === 2 ? 'Services' : 
                   step === 3 ? 'Security' : 
                   step === 4 ? 'Review' : 'Deploy'}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Hidden Edition Toggle for Demo */}
        <div style={{ display: 'none' }}>
          <button onClick={() => setEdition('community')}>Community</button>
          <button onClick={() => setEdition('pro')}>Pro</button>
        </div>

        {/* Main Content */}
        <main className="main-content">
          <div className="wizard-content">
            {/* Step 1: Basic Information */}
            {currentStep === 1 && (
              <div className="step-content">
                <h2 className="step-title">Basic Information</h2>
                <p className="step-description">Set up your admin credentials and primary domain</p>
                
                <div className={`form-group ${validationErrors.adminEmail ? 'error' : config.adminEmail && validateEmail(config.adminEmail).valid ? 'valid' : ''} ${validating ? 'loading' : ''}`}>
                  <label htmlFor="adminEmail">Admin Email Address</label>
                  <input
                    type="email"
                    id="adminEmail"
                    value={config.adminEmail}
                    onChange={(e) => handleInputChange('adminEmail', e.target.value)}
                    placeholder="admin@example.com"
                    className={validationErrors.adminEmail ? 'error' : config.adminEmail && validateEmail(config.adminEmail).valid ? 'valid' : ''}
                    aria-describedby={validationErrors.adminEmail ? 'adminEmail-error' : 'adminEmail-help'}
                    aria-invalid={!!validationErrors.adminEmail}
                  />
                  <p id="adminEmail-help" className="helper-text">This email will be used for admin access to all services</p>
                  {validationErrors.adminEmail && (
                    <div id="adminEmail-error" className="error-message" role="alert">{validationErrors.adminEmail}</div>
                  )}
                </div>
                
                <div className={`form-group ${validationErrors.adminPassword ? 'error' : config.adminPassword ? 'valid' : ''}`}>
                  <label htmlFor="adminPassword">Admin Password <span className="optional">(Optional)</span></label>
                  <input
                    type="password"
                    id="adminPassword"
                    value={config.adminPassword}
                    onChange={(e) => handleInputChange('adminPassword', e.target.value)}
                    placeholder="Leave blank to auto-generate"
                    className={validationErrors.adminPassword ? 'error' : config.adminPassword ? 'valid' : ''}
                    aria-describedby={validationErrors.adminPassword ? 'adminPassword-error' : 'adminPassword-help'}
                    aria-invalid={!!validationErrors.adminPassword}
                  />
                  <p id="adminPassword-help" className="helper-text">Set a custom password or leave blank to generate a secure one automatically</p>
                  {validationErrors.adminPassword && (
                    <div id="adminPassword-error" className="error-message" role="alert">{validationErrors.adminPassword}</div>
                  )}
                </div>
                
                <div className={`form-group ${validationErrors.domain ? 'error' : isDomainValid && !isDomainValidating ? 'valid' : ''} ${isDomainValidating || validating ? 'loading' : ''}`}>
                  <label htmlFor="domain">
                    Primary Domain
                    {isDomainValidating && <span className="validation-status"> (validating...)</span>}
                  </label>
                  <input
                    type="text"
                    id="domain"
                    value={config.domain}
                    onChange={(e) => handleInputChange('domain', e.target.value)}
                    placeholder={expertMode ? "example.com or app.staging.dev.example.com" : "example.com or localhost"}
                    className={validationErrors.domain ? 'error' : isDomainValid && !isDomainValidating ? 'valid' : ''}
                    aria-describedby={validationErrors.domain ? 'domain-error' : 'domain-help'}
                    aria-invalid={!!validationErrors.domain}
                  />
                  <p id="domain-help" className="helper-text">
                    {expertMode 
                      ? "Enter your domain name (supports deep subdomains up to 4 levels)"
                      : "Enter your domain name or use 'localhost' for local development"}
                  </p>
                  {validationErrors.domain && (
                    <div id="domain-error" className="error-message" role="alert">{validationErrors.domain}</div>
                  )}
                </div>
                
                <div className="form-group">
                  <label>SSL Certificate Provider</label>
                  <div className="ssl-options">
                    <div 
                      className={`ssl-option ${config.sslProvider === 'none' ? 'selected' : ''}`}
                      onClick={() => handleInputChange('sslProvider', 'none')}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          handleInputChange('sslProvider', 'none');
                        }
                      }}
                      tabIndex={0}
                      role="radio"
                      aria-checked={config.sslProvider === 'none'}
                      aria-labelledby="ssl-none-title"
                      aria-describedby="ssl-none-desc"
                    >
                      <div className="ssl-option-header">
                        <div id="ssl-none-title" className="ssl-option-title">No SSL</div>
                        {config.sslProvider === 'none' && <div className="ssl-option-checkmark">✓</div>}
                      </div>
                      <div id="ssl-none-desc" className="ssl-option-description">Local development only</div>
                    </div>
                    
                    <div 
                      className={`ssl-option disabled`}
                      onClick={(e) => {
                        e.preventDefault();
                        // Disabled - coming soon
                      }}
                      onKeyDown={(e) => {
                        e.preventDefault();
                      }}
                      tabIndex={-1}
                      role="radio"
                      aria-checked={false}
                      aria-labelledby="ssl-npm-title"
                      aria-describedby="ssl-npm-desc"
                      aria-disabled={true}
                    >
                      <div className="ssl-option-header">
                        <div id="ssl-npm-title" className="ssl-option-title">Nginx Proxy Manager</div>
                        <div className="ssl-option-badge coming-soon">Coming Soon</div>
                      </div>
                      <div id="ssl-npm-desc" className="ssl-option-description">Automatic SSL certificates with Let's Encrypt</div>
                    </div>
                    
                    <div 
                      className={`ssl-option ${config.sslProvider === 'cloudflare-tunnel' ? 'selected' : ''}`}
                      onClick={() => {
                        if (edition !== 'community') {
                          handleInputChange('sslProvider', 'cloudflare-tunnel');
                        }
                      }}
                      onKeyDown={(e) => {
                        if (edition !== 'community' && (e.key === 'Enter' || e.key === ' ')) {
                          e.preventDefault();
                          handleInputChange('sslProvider', 'cloudflare-tunnel');
                        }
                      }}
                      tabIndex={edition === 'community' ? -1 : 0}
                      role="radio"
                      aria-checked={config.sslProvider === 'cloudflare-tunnel'}
                      aria-labelledby="ssl-cf-tunnel-title"
                      aria-describedby="ssl-cf-tunnel-desc"
                      aria-disabled={edition === 'community'}
                    >
                      <div className="ssl-option-header">
                        <div id="ssl-cf-tunnel-title" className="ssl-option-title">Cloudflare Tunnel</div>
                        {edition === 'community' && <div className="ssl-option-badge premium">Pro/Enterprise</div>}
                        {config.sslProvider === 'cloudflare-tunnel' && edition !== 'community' && <div className="ssl-option-checkmark">✓</div>}
                      </div>
                      <div id="ssl-cf-tunnel-desc" className="ssl-option-description">Zero-config secure tunneling via Cloudflare</div>
                    </div>
                    
                    <div 
                      className={`ssl-option ${config.sslProvider === 'cloudflare-dns' ? 'selected' : ''} ${edition === 'community' ? 'disabled' : ''}`}
                      onClick={() => {
                        console.log('Cloudflare DNS clicked, edition:', edition);
                        if (edition !== 'community') {
                          handleInputChange('sslProvider', 'cloudflare-dns');
                        } else {
                          console.log('Blocked: Community edition');
                        }
                      }}
                      onKeyDown={(e) => {
                        if (edition !== 'community' && (e.key === 'Enter' || e.key === ' ')) {
                          e.preventDefault();
                          handleInputChange('sslProvider', 'cloudflare-dns');
                        }
                      }}
                      tabIndex={edition === 'community' ? -1 : 0}
                      role="radio"
                      aria-checked={config.sslProvider === 'cloudflare-dns'}
                      aria-labelledby="ssl-cf-dns-title"
                      aria-describedby="ssl-cf-dns-desc"
                      aria-disabled={edition === 'community'}
                    >
                      <div className="ssl-option-header">
                        <div id="ssl-cf-dns-title" className="ssl-option-title">Cloudflare DNS</div>
                        {edition === 'community' && <div className="ssl-option-badge premium">Pro/Enterprise</div>}
                        {config.sslProvider === 'cloudflare-dns' && edition !== 'community' && <div className="ssl-option-checkmark">✓</div>}
                      </div>
                      <div id="ssl-cf-dns-desc" className="ssl-option-description">Enterprise-grade SSL automation via Cloudflare API</div>
                    </div>
                  </div>
                </div>

                {/* Expert Mode Toggle */}
                <div className="expert-mode-section">
                  <div className="expert-mode-toggle">
                    <label className="toggle-switch">
                      <input
                        type="checkbox"
                        checked={expertMode}
                        onChange={(e) => setExpertMode(e.target.checked)}
                        aria-describedby="expert-mode-desc"
                      />
                      <span className="toggle-slider"></span>
                      <span className="toggle-label">Expert Mode</span>
                    </label>
                    <p id="expert-mode-desc" className="helper-text">Enable advanced configuration options</p>
                  </div>

                  {/* Expert Mode Options */}
                  {expertMode && (
                    <div className="expert-options">
                      <div className="expert-option">
                        <label className="checkbox-label">
                          <input
                            type="checkbox"
                            checked={config.skipDnsValidation}
                            onChange={(e) => handleInputChange('skipDnsValidation', e.target.checked)}
                          />
                          <span>Skip DNS validation</span>
                        </label>
                        <p className="helper-text">Bypass DNS checks for domains (useful for internal networks)</p>
                      </div>
                      
                      <div className="expert-info">
                        <h4>Expert Mode Features:</h4>
                        <ul>
                          <li>Support for deep subdomains (e.g., app.staging.dev.example.com)</li>
                          <li>Ability to skip DNS validation for internal domains</li>
                          <li>Advanced SSL configuration options</li>
                          <li>Custom port configurations (coming soon)</li>
                        </ul>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Step 2: Service Configuration */}
            {currentStep === 2 && (
              <div className="step-content">
                <h2 className="step-title">Service Configuration</h2>
                <p className="step-description">Configure your service URLs and access points</p>
                
                <div className="service-urls">
                  <div className="url-group">
                    <label>Stack Manager URL</label>
                    <input
                      type="text"
                      value={config.stackManagerUrl}
                      onChange={(e) => handleInputChange('stackManagerUrl', e.target.value)}
                      placeholder="stack.example.com"
                    />
                    <p className="helper-text">Main management interface for your AI stack</p>
                  </div>
                  
                  <div className="url-group">
                    <label>n8n Automation URL</label>
                    <input
                      type="text"
                      value={config.n8nUrl}
                      onChange={(e) => handleInputChange('n8nUrl', e.target.value)}
                      placeholder="n8n.example.com"
                    />
                    <p className="helper-text">Workflow automation and integration platform</p>
                  </div>
                  
                  <div className="url-group">
                    <label>Grafana Monitoring URL</label>
                    <input
                      type="text"
                      value={config.grafanaUrl}
                      onChange={(e) => handleInputChange('grafanaUrl', e.target.value)}
                      placeholder="grafana.example.com"
                    />
                    <p className="helper-text">Monitoring and analytics dashboard</p>
                  </div>
                </div>

                {/* Cloudflare Configuration */}
                {(config.sslProvider === 'cloudflare-tunnel' || config.sslProvider === 'cloudflare-dns') && (
                  <div className="cloudflare-config">
                    <h3 className="cloudflare-title">☁️ Cloudflare Integration</h3>
                    
                    <div className="cloudflare-instructions">
                      <h4>Setup Instructions:</h4>
                      <ol>
                        <li>Log in to your <a href="https://dash.cloudflare.com" target="_blank" rel="noopener noreferrer">Cloudflare Dashboard</a></li>
                        <li>Navigate to your domain to find the Zone ID</li>
                        <li>Create an API Token with the required permissions</li>
                        {config.sslProvider === 'cloudflare-tunnel' && (
                          <li>For Tunnel: Get your Account ID from the dashboard sidebar</li>
                        )}
                      </ol>
                      
                      <div className="help-links">
                        <a href="https://developers.cloudflare.com/fundamentals/api/get-started/create-token/" target="_blank" rel="noopener noreferrer">
                          📖 API Token Guide
                        </a>
                        <a href="https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/" target="_blank" rel="noopener noreferrer">
                          🔍 Find Zone & Account IDs
                        </a>
                        {config.sslProvider === 'cloudflare-tunnel' && (
                          <a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/" target="_blank" rel="noopener noreferrer">
                            🚇 Tunnel Documentation
                          </a>
                        )}
                      </div>
                    </div>
                    
                    <div className="cloudflare-form">
                      <div className="form-group">
                        <label>API Token <span className="required">*</span></label>
                        <input
                          type="password"
                          value={config.cloudflareApiToken || ''}
                          onChange={(e) => handleInputChange('cloudflareApiToken', e.target.value)}
                          placeholder="Your Cloudflare API token"
                        />
                        <p className="helper-text">Minimum permissions required: DNS:Edit for your zone</p>
                      </div>
                      
                      <div className="form-group">
                        <label>Zone ID <span className="required">*</span></label>
                        <input
                          type="text"
                          value={config.cloudflareZoneId || ''}
                          onChange={(e) => handleInputChange('cloudflareZoneId', e.target.value)}
                          placeholder="e.g., 023e105f4ecef8ad9ca31a8372d0c353"
                        />
                        <p className="helper-text">32-character string found in your domain's overview page</p>
                      </div>
                      
                      {config.sslProvider === 'cloudflare-tunnel' && (
                        <>
                          <div className="form-group">
                            <label>Account ID <span className="required">*</span></label>
                            <input
                              type="text"
                              value={config.cloudflareAccountId || ''}
                              onChange={(e) => handleInputChange('cloudflareAccountId', e.target.value)}
                              placeholder="e.g., 372e105f4ecef8ad9ca31a8372d0c353"
                            />
                            <p className="helper-text">32-character string found in the dashboard sidebar</p>
                          </div>
                          
                          <div className="form-group">
                            <label>Existing Tunnel Token <span className="optional">(Optional)</span></label>
                            <input
                              type="password"
                              value={config.cloudflareTunnelToken || ''}
                              onChange={(e) => handleInputChange('cloudflareTunnelToken', e.target.value)}
                              placeholder="Leave blank to create a new tunnel"
                            />
                            <p className="helper-text">If you already have a tunnel, paste its token here</p>
                          </div>
                        </>
                      )}
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Step 3: Security Configuration */}
            {currentStep === 3 && (
              <div className="step-content">
                <h2 className="step-title">Security Configuration</h2>
                <p className="step-description">Configure passwords and security settings</p>
                
                <div className="security-options">
                  <div className="security-option">
                    <div className="checkbox-group">
                      <div 
                        className={`checkbox ${config.useCustomPasswords ? 'checked' : ''}`}
                        onClick={() => handleInputChange('useCustomPasswords', !config.useCustomPasswords)}
                      ></div>
                      <label>Use custom application passwords</label>
                    </div>
                    <p className="helper-text">If not selected, secure random passwords will be generated automatically</p>
                    
                    {config.useCustomPasswords && (
                      <div className="custom-passwords-container">
                        <div className="form-group">
                          <label htmlFor="postgresPassword">PostgreSQL Password</label>
                          <input
                            type="password"
                            id="postgresPassword"
                            value={config.postgresPassword || ''}
                            onChange={(e) => handleInputChange('postgresPassword', e.target.value)}
                            placeholder="Enter PostgreSQL password"
                          />
                        </div>
                        
                        <div className="form-group">
                          <label htmlFor="redisPassword">Redis Password</label>
                          <input
                            type="password"
                            id="redisPassword"
                            value={config.redisPassword || ''}
                            onChange={(e) => handleInputChange('redisPassword', e.target.value)}
                            placeholder="Enter Redis password"
                          />
                        </div>
                        
                        <div className="form-group">
                          <label htmlFor="jwtSecret">JWT Secret</label>
                          <input
                            type="password"
                            id="jwtSecret"
                            value={config.jwtSecret || ''}
                            onChange={(e) => handleInputChange('jwtSecret', e.target.value)}
                            placeholder="Enter JWT secret (min 32 characters)"
                          />
                          <p className="helper-text">Used for authentication tokens</p>
                        </div>
                      </div>
                    )}
                  </div>
                  
                  {/* MFA option hidden for now
                  <div className="security-option">
                    <div className="checkbox-group">
                      <div 
                        className={`checkbox ${config.enableMfa ? 'checked' : ''}`}
                        onClick={() => handleInputChange('enableMfa', !config.enableMfa)}
                      ></div>
                      <label>Enable Multi-Factor Authentication</label>
                    </div>
                    <p className="helper-text">Add an extra layer of security to admin accounts</p>
                  </div>
                  */}
                </div>
              </div>
            )}

            {/* Step 4: Review & Deploy */}
            {currentStep === 4 && (
              <div className="step-content">
                <h2 className="step-title">Review & Deploy</h2>
                <p className="step-description">Review your configuration and start deployment</p>
                
                <div className="review-section">
                  <h3 className="review-title">Basic Configuration</h3>
                  <div className="review-item">
                    <span className="review-label">Edition:</span>
                    <span className="review-value">{edition === 'community' ? 'Community' : 'Premium'}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">Admin Email:</span>
                    <span className="review-value">{config.adminEmail}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">Admin Password:</span>
                    <span className="review-value">{config.adminPassword ? '••••••••' : 'Auto-generate'}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">Domain:</span>
                    <span className="review-value">{config.domain}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">SSL Provider:</span>
                    <span className="review-value">
                      {config.sslProvider === 'none' && 'No SSL'}
                      {config.sslProvider === 'npm' && 'Nginx Proxy Manager'}
                      {config.sslProvider === 'cloudflare-tunnel' && 'Cloudflare Tunnel'}
                      {config.sslProvider === 'cloudflare-dns' && 'Cloudflare DNS'}
                    </span>
                  </div>
                </div>
                
                <div className="review-section">
                  <h3 className="review-title">Service URLs</h3>
                  <div className="review-item">
                    <span className="review-label">Stack Manager:</span>
                    <span className="review-value">{config.stackManagerUrl}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">n8n Automation:</span>
                    <span className="review-value">{config.n8nUrl}</span>
                  </div>
                  <div className="review-item">
                    <span className="review-label">Grafana Monitoring:</span>
                    <span className="review-value">{config.grafanaUrl}</span>
                  </div>
                </div>

                {/* Pre-flight Check Results */}
                {preflightStatus && (
                  <div className={`review-section preflight-results ${preflightStatus.passed ? 'passed' : 'failed'}`}>
                    <h3 className="review-title">System Resource Checks</h3>
                    
                    {/* Overall Status */}
                    <div className="preflight-summary">
                      {preflightStatus.passed ? (
                        <div className="preflight-passed">
                          <span className="preflight-icon">✅</span>
                          <span>{preflightStatus.summary.message}</span>
                        </div>
                      ) : (
                        <div className="preflight-failed">
                          <span className="preflight-icon">❌</span>
                          <span>{preflightStatus.summary.message}</span>
                        </div>
                      )}
                    </div>

                    {/* Individual Checks */}
                    {preflightStatus.checks && (
                      <div className="preflight-checks">
                        <div className="check-item">
                          <span className="check-label">Disk Space:</span>
                          <span className={`check-value ${preflightStatus.checks.disk.sufficient ? 'good' : 'bad'}`}>
                            {preflightStatus.checks.disk.message}
                          </span>
                        </div>
                        <div className="check-item">
                          <span className="check-label">Memory:</span>
                          <span className={`check-value ${preflightStatus.checks.memory.sufficient ? 'good' : 'bad'}`}>
                            {preflightStatus.checks.memory.message}
                          </span>
                        </div>
                        <div className="check-item">
                          <span className="check-label">Docker:</span>
                          <span className={`check-value ${preflightStatus.checks.docker.available ? 'good' : 'bad'}`}>
                            {preflightStatus.checks.docker.message}
                          </span>
                        </div>
                        <div className="check-item">
                          <span className="check-label">Network:</span>
                          <span className={`check-value ${preflightStatus.checks.network.criticalAccessible ? 'good' : 'bad'}`}>
                            {preflightStatus.checks.network.message}
                          </span>
                        </div>
                        {preflightStatus.checks.ports.conflicts.length > 0 && (
                          <div className="check-item">
                            <span className="check-label">Ports:</span>
                            <span className="check-value warning">
                              {preflightStatus.checks.ports.message}
                            </span>
                          </div>
                        )}
                      </div>
                    )}

                    {/* Critical Issues */}
                    {preflightStatus.summary.criticalIssues && preflightStatus.summary.criticalIssues.length > 0 && (
                      <div className="preflight-issues">
                        <h4>Critical Issues (Must Fix):</h4>
                        <ul>
                          {preflightStatus.summary.criticalIssues.map((issue, idx) => (
                            <li key={idx}>{issue}</li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {/* Warnings */}
                    {preflightStatus.summary.warnings && preflightStatus.summary.warnings.length > 0 && (
                      <div className="preflight-warnings">
                        <h4>Warnings:</h4>
                        <ul>
                          {preflightStatus.summary.warnings.map((warning, idx) => (
                            <li key={idx}>{warning}</li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                )}

                {/* Run Pre-flight Check Button */}
                {!preflightStatus && (
                  <div className="preflight-action">
                    <button 
                      className={`btn btn-secondary ${checkingPreflight ? 'loading' : ''}`}
                      onClick={runPreflightChecks}
                      disabled={checkingPreflight}
                      aria-label="Run system resource checks"
                    >
                      {checkingPreflight ? 'Checking System...' : '🔍 Check System Resources'}
                    </button>
                  </div>
                )}
                
                {/* DNS Propagation Check */}
                {config.domain !== 'localhost' && (
                  <div className="review-section">
                    <h3 className="review-title">DNS Propagation Check</h3>
                    <div className="dns-check-content">
                      <p className="helper-text">
                        Check if your domain DNS records have propagated before deployment
                      </p>
                      <button 
                        className="btn btn-secondary"
                        onClick={async () => {
                          setCheckingDns(true)
                          const domains = [
                            config.stackManagerUrl,
                            config.n8nUrl,
                            config.grafanaUrl
                          ].filter(url => url && !url.includes('localhost'))
                          
                          const result = await checkDnsPropagation(domains)
                          setDnsStatus(result.domains || {})
                          setCheckingDns(false)
                        }}
                        disabled={checkingDns}
                      >
                        {checkingDns ? '🔍 Checking DNS...' : '🌐 Check DNS Propagation'}
                      </button>
                      
                      {Object.keys(dnsStatus).length > 0 && (
                        <div className="dns-results">
                          {Object.entries(dnsStatus).map(([domain, status]) => (
                            <div key={domain} className="dns-result-item">
                              <div className="dns-domain">{domain}</div>
                              <div className={`dns-status ${status.propagated ? 'success' : 'pending'}`}>
                                {status.isLocal ? (
                                  '✅ Local domain'
                                ) : status.propagated ? (
                                  <>
                                    ✅ DNS Configured
                                    {status.ip && <div className="dns-ip">IP: {status.ip}</div>}
                                    {status.pointsToServer !== undefined && (
                                      <div className="dns-server-check">
                                        {status.pointsToServer ? '✓ Points to this server' : '⚠️ Points to different server'}
                                      </div>
                                    )}
                                  </>
                                ) : (
                                  <>
                                    ⏳ DNS Not Configured
                                    <div className="dns-message">{status.message || 'Configure DNS A record'}</div>
                                  </>
                                )}
                              </div>
                            </div>
                          ))}
                          {config.sslProvider === 'cloudflare-tunnel' || config.sslProvider === 'cloudflare-dns' ? (
                            <p className="dns-note">
                              <strong>Note:</strong> Cloudflare will handle DNS configuration automatically during deployment.
                            </p>
                          ) : (
                            <p className="dns-note">
                              <strong>Required:</strong> Point DNS A records to server IP before deployment.
                            </p>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                )}
                
                <div className="deployment-info">
                  <p><strong>⏱️ Estimated deployment time:</strong> 15-30 minutes</p>
                  <p><strong>📋 Requirements:</strong> Docker or Podman must be installed</p>
                  {config.domain !== 'localhost' && !Object.values(dnsStatus).every(s => s.propagated) && (
                    <p className="warning-text">
                      <strong>⚠️ Warning:</strong> DNS may not be fully propagated. Deployment can proceed, but services may not be accessible via domain names immediately.
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* Step 5: Deployment Progress */}
            {currentStep === 5 && (
              <div className="step-content">
                <h2 className="step-title">Deployment Progress</h2>
                <p className="step-description">Installing and configuring your AI Stack</p>
                
                {deploymentStatus === 'completed' && (
                  <div className="success-state">
                    <div className="success-icon">✅</div>
                    <h3 className="success-title">Deployment Successful!</h3>
                    <p className="success-message">Your AI Stack is now running and ready to use.</p>
                    <div className="success-actions">
                      <button className="btn btn-success">
                        🚀 Open Stack Manager
                      </button>
                      <button className="btn btn-secondary" onClick={exportConfig}>
                        💾 Save Configuration
                      </button>
                      <button className="btn btn-secondary" onClick={() => downloadDeploymentLogs('full')}>
                        📄 Download Full Log
                      </button>
                      <button className="btn btn-secondary" onClick={() => downloadDeploymentLogs('anonymized')}>
                        🔒 Download Anonymized Log
                      </button>
                    </div>
                    {telemetryStatus && telemetryStatus.trackingId && (
                      <div className="telemetry-info">
                        <p className="telemetry-message">
                          ✓ Anonymized telemetry sent. Tracking ID: <code>{telemetryStatus.trackingId}</code>
                        </p>
                      </div>
                    )}
                  </div>
                )}
                
                {deploymentStatus === 'failed' && (
                  <div className="failed-state">
                    <div className="failed-icon">❌</div>
                    <h3 className="failed-title">Deployment Failed</h3>
                    <p className="failed-message">The deployment encountered an error. You can try again or rollback to a previous state.</p>
                    <div className="failed-actions">
                      <button className="btn btn-primary" onClick={() => startDeployment()}>
                        🔄 Retry Deployment
                      </button>
                      {snapshots.length > 0 && (
                        <button className="btn btn-secondary" onClick={() => setShowRollbackModal(true)}>
                          ⏪ Rollback to Previous State
                        </button>
                      )}
                      <button className="btn btn-secondary" onClick={() => downloadDeploymentLogs('full')}>
                        📄 Download Full Log
                      </button>
                      <button className="btn btn-secondary" onClick={() => downloadDeploymentLogs('anonymized')}>
                        🔒 Download Anonymized Report
                      </button>
                    </div>
                  </div>
                )}
                
                <div className="deployment-logs">
                  <div className="logs-header">
                    <h3 className="logs-title">📋 Deployment Logs</h3>
                    <div className="export-buttons">
                      <button className="export-btn" onClick={exportLogs}>
                        📥 Export Logs
                      </button>
                      <button className="export-btn" onClick={exportConfig}>
                        📄 Export Config
                      </button>
                    </div>
                  </div>
                  <div className="logs-content">
                    {deploymentLogs.map((log, index) => (
                      <div key={index} className="log-line">
                        {log}
                      </div>
                    ))}
                    {deploymentStatus === 'deploying' && (
                      <div className="log-line">
                        <span className="spinner"></span> Deployment in progress...
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* Navigation Buttons */}
            <div className="nav-buttons">
              {currentStep > 1 && currentStep < 5 && (
                <button 
                  className="btn btn-secondary" 
                  onClick={prevStep}
                  aria-label="Go to previous step"
                >
                  ← Previous
                </button>
              )}
              
              <div></div>
              
              {currentStep < 4 && (
                <button 
                  className={`btn btn-primary ${validating ? 'loading' : ''}`} 
                  onClick={nextStep}
                  disabled={validating}
                  aria-label="Go to next step"
                >
                  {validating ? 'Validating...' : 'Next Step →'}
                </button>
              )}
              
              {currentStep === 4 && (
                <button 
                  className={`btn btn-primary ${deploymentStatus === 'deploying' ? 'loading' : ''}`} 
                  onClick={startDeployment}
                  disabled={deploymentStatus === 'deploying'}
                  aria-label="Start deployment process"
                >
                  {deploymentStatus === 'deploying' ? 'Deploying...' : '🚀 Deploy Stack'}
                </button>
              )}
            </div>
          </div>
        </main>
        
        {/* Footer */}
        <footer className="app-footer">
          <div className="footer-content">
            <div className="footer-copyright">
              &copy; {new Date().getFullYear()} Stack Masters
            </div>
            <div className="footer-links">
              <span className="footer-label">Need Support?</span>
              <a 
                href="https://www.skool.com/ai-stack-masters" 
                target="_blank" 
                rel="noopener noreferrer"
                className="footer-link"
              >
                Free Community
              </a>
              <span className="footer-separator">•</span>
              <a 
                href="https://www.skool.com/ai-stack-master-pros" 
                target="_blank" 
                rel="noopener noreferrer"
                className="footer-link footer-link-pro"
              >
                Pro Community
              </a>
            </div>
          </div>
        </footer>
      </div>

      {/* Rollback Modal */}
      {showRollbackModal && (
        <div className="modal-overlay" onClick={() => !rollbackInProgress && setShowRollbackModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2 className="modal-title">🔄 Rollback Deployment</h2>
              {!rollbackInProgress && (
                <button 
                  className="modal-close"
                  onClick={() => setShowRollbackModal(false)}
                  aria-label="Close modal"
                >
                  ×
                </button>
              )}
            </div>
            
            <div className="modal-body">
              {snapshots.length > 0 ? (
                <>
                  <p className="modal-description">
                    Select a checkpoint to rollback to. This will restore your deployment to the selected state.
                  </p>
                  
                  <div className="snapshots-list">
                    {snapshots.map((snapshot) => (
                      <div key={snapshot.id} className="snapshot-item">
                        <div className="snapshot-info">
                          <h4 className="snapshot-step">Step {snapshot.step}</h4>
                          <p className="snapshot-time">
                            {new Date(snapshot.timestamp).toLocaleString()}
                          </p>
                        </div>
                        <button
                          className="btn btn-sm btn-primary"
                          onClick={() => performRollback(snapshot.id)}
                          disabled={rollbackInProgress}
                        >
                          Rollback to This Point
                        </button>
                      </div>
                    ))}
                  </div>
                  
                  {rollbackInProgress && (
                    <div className="rollback-progress">
                      <div className="spinner"></div>
                      <p>Rolling back deployment...</p>
                    </div>
                  )}
                </>
              ) : (
                <p className="no-snapshots">No rollback points available.</p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default App

