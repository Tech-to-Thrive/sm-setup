/**
 * Input Validation Middleware - One-way pass valve system
 * Only allows validated, safe input through to the application
 * Blocks any potentially dangerous input at the gate
 */

// Import shared validators for consistency (CommonJS version)
const sharedValidators = require('../shared/validators.cjs');

// Strict validation patterns for different input types
const ValidationPatterns = {
  // Use shared validators regex patterns
  domain: sharedValidators.DOMAIN_REGEX,
  email: sharedValidators.EMAIL_REGEX,
  
  // Admin name: letters, spaces, hyphens, apostrophes only
  adminName: /^[a-zA-Z\s'-]{1,50}$/,
  
  // Password: any characters but limited length
  password: /^.{8,128}$/,
  
  // Alphanumeric with underscores (for IDs, tokens)
  alphanumeric: /^[a-zA-Z0-9_-]+$/,
  
  // Hex string (for tokens, hashes)
  hex: /^[a-f0-9]+$/,
  
  // Service names
  serviceName: /^[a-zA-Z0-9-_]{1,50}$/,
  
  // URLs
  url: /^https?:\/\/[a-zA-Z0-9.-]+(:[0-9]+)?(\/[a-zA-Z0-9._~:/?#[\]@!$&'()*+,;=-]*)?$/,
  
  // IP addresses
  ipAddress: /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/,
  
  // Port numbers
  port: /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/,
  
  // Edition values
  edition: /^(community|pro)$/,
  
  // SSL providers
  sslProvider: /^(none|npm|cloudflare-tunnel|external)$/,
  
  // Zone IDs (alphanumeric)
  zoneId: /^[a-zA-Z0-9]{32}$/,
  
  // Account IDs
  accountId: /^[a-zA-Z0-9-]{36}$/,
  
  // API tokens (longer hex or base64)
  apiToken: /^[a-zA-Z0-9_\-+=\/]{40,}$/
};

// Maximum lengths for string inputs
const MaxLengths = {
  domain: 253,
  email: 254,
  adminName: 50,
  password: 128,
  serviceName: 50,
  url: 2048,
  apiToken: 500,
  general: 1000
};

// Dangerous patterns to always reject
const DangerousPatterns = [
  // Shell injection attempts
  /[;&|`$()<>\[\]{}*?!~\\]/,
  // Path traversal
  /\.\.[\/\\]/,
  // Null bytes
  /\x00/,
  // Control characters
  /[\x01-\x1f\x7f]/,
  // SQL injection patterns
  /(\b(union|select|insert|update|delete|drop|create|alter|exec|script)\b)/i,
  // Script tags
  /<script[^>]*>|<\/script>/i,
  // Common command injection
  /\b(wget|curl|nc|netcat|bash|sh|cmd|powershell)\b/i
];

/**
 * Input validation middleware factory
 * Creates middleware that validates specific fields against patterns
 */
function createInputValidator(fieldValidations) {
  return (req, res, next) => {
    try {
      // Check all specified fields
      for (const [field, pattern] of Object.entries(fieldValidations)) {
        const value = getFieldValue(req, field);
        
        if (value !== undefined && value !== null && value !== '') {
          // Convert to string for validation
          const stringValue = String(value);
          
          // Check against dangerous patterns first
          for (const dangerous of DangerousPatterns) {
            if (dangerous.test(stringValue)) {
              return res.status(400).json({
                error: `Invalid ${field}: contains potentially dangerous characters`,
                field,
                code: 'DANGEROUS_INPUT'
              });
            }
          }
          
          // Check length
          const maxLength = MaxLengths[field] || MaxLengths.general;
          if (stringValue.length > maxLength) {
            return res.status(400).json({
              error: `Invalid ${field}: exceeds maximum length of ${maxLength}`,
              field,
              code: 'INPUT_TOO_LONG'
            });
          }
          
          // Check against specific pattern
          const validationPattern = ValidationPatterns[pattern] || pattern;
          if (!validationPattern.test(stringValue)) {
            return res.status(400).json({
              error: `Invalid ${field}: format not allowed`,
              field,
              code: 'INVALID_FORMAT',
              hint: getFormatHint(pattern)
            });
          }
          
          // Sanitize and store cleaned value
          req.validatedInputs = req.validatedInputs || {};
          req.validatedInputs[field] = stringValue.trim();
        }
      }
      
      next();
    } catch (error) {
      console.error('Input validation error:', error);
      res.status(500).json({ 
        error: 'Input validation failed',
        code: 'VALIDATION_ERROR'
      });
    }
  };
}

/**
 * Get field value from request (supports nested paths)
 */
function getFieldValue(req, fieldPath) {
  const parts = fieldPath.split('.');
  let value = req;
  
  for (const part of parts) {
    value = value?.[part];
    if (value === undefined) break;
  }
  
  return value;
}

/**
 * Get user-friendly format hints
 */
function getFormatHint(pattern) {
  const hints = {
    domain: 'Use format: example.com or sub.example.com',
    email: 'Use format: user@example.com',
    adminName: 'Use only letters, spaces, hyphens',
    password: 'Must be 8-128 characters',
    hex: 'Use only hexadecimal characters (0-9, a-f)',
    port: 'Use port number between 1-65535',
    url: 'Use format: http://example.com or https://example.com',
    ipAddress: 'Use format: 192.168.1.1'
  };
  
  return hints[pattern] || 'Invalid format';
}

/**
 * Global input sanitizer middleware
 * Applies to all requests to catch any unvalidated input
 */
function globalInputSanitizer() {
  return (req, res, next) => {
    // Recursively check all input for dangerous patterns
    const checkValue = (obj, path = '') => {
      if (typeof obj === 'string') {
        // Check for dangerous patterns
        for (const pattern of DangerousPatterns) {
          if (pattern.test(obj)) {
            throw new Error(`Dangerous input detected at ${path}`);
          }
        }
        // Check excessive length
        if (obj.length > MaxLengths.general) {
          throw new Error(`Input too long at ${path}`);
        }
      } else if (Array.isArray(obj)) {
        obj.forEach((item, index) => checkValue(item, `${path}[${index}]`));
      } else if (obj && typeof obj === 'object') {
        Object.entries(obj).forEach(([key, value]) => {
          checkValue(value, path ? `${path}.${key}` : key);
        });
      }
    };
    
    try {
      // Check all input sources
      if (req.body) checkValue(req.body, 'body');
      if (req.query) checkValue(req.query, 'query');
      if (req.params) checkValue(req.params, 'params');
      
      next();
    } catch (error) {
      console.error('Global input validation failed:', error.message);
      res.status(400).json({
        error: 'Invalid input detected',
        code: 'DANGEROUS_INPUT_GLOBAL'
      });
    }
  };
}

/**
 * Enhanced validator that uses shared validation logic
 */
function createEnhancedValidator(validations) {
  return (req, res, next) => {
    const errors = {};
    
    // Run each validation
    for (const [field, validatorName] of Object.entries(validations)) {
      const value = getFieldValue(req, field);
      
      if (value !== undefined && value !== null && value !== '') {
        // Use shared validator if available
        if (sharedValidators[validatorName]) {
          const result = sharedValidators[validatorName](value);
          if (!result.valid) {
            errors[field] = result.message;
          }
        }
      }
    }
    
    if (Object.keys(errors).length > 0) {
      return res.status(400).json({
        error: 'Validation failed',
        errors
      });
    }
    
    next();
  };
}

/**
 * Pre-configured validators for common endpoints
 */
const validators = {
  // Deployment configuration validator
  deployment: createInputValidator({
    'body.domain': 'domain',
    'body.adminEmail': 'email',
    'body.adminName': 'adminName',
    'body.adminPassword': 'password',
    'body.edition': 'edition',
    'body.sslProvider': 'sslProvider'
  }),
  
  // Enhanced deployment validator using shared logic
  deploymentEnhanced: createEnhancedValidator({
    'body.domain': 'validateDomain',
    'body.adminEmail': 'validateEmail',
    'body.adminName': 'validateAdminName',
    'body.adminPassword': 'validatePassword'
  }),
  
  // Domain validation endpoint
  validateDomain: createInputValidator({
    'body.domain': 'domain'
  }),
  
  // Service URL validation
  validateServiceUrl: createInputValidator({
    'body.url': 'url',
    'body.service': 'serviceName',
    'body.edition': 'edition',
    'body.sslProvider': 'sslProvider'
  }),
  
  // Cloudflare validation
  validateCloudflare: createInputValidator({
    'body.apiToken': 'apiToken',
    'body.zoneId': 'zoneId',
    'body.accountId': 'accountId'
  }),
  
  // Token validation
  validateToken: createInputValidator({
    'query.token': 'hex',
    'params.token': 'hex',
    'body.token': 'hex'
  })
};

module.exports = {
  createInputValidator,
  globalInputSanitizer,
  validators,
  ValidationPatterns,
  DangerousPatterns
};