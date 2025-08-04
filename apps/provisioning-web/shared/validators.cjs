/**
 * Shared validation logic for frontend and backend (CommonJS version)
 * Ensures consistent validation across the entire application
 */

// Domain validation regex - matches backend validators.js line 12
const DOMAIN_REGEX = /^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.)*[a-zA-Z]{2,}$/;

// Email validation regex
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Password requirements
const PASSWORD_MIN_LENGTH = 8;
const PASSWORD_REGEX_UPPER = /[A-Z]/;
const PASSWORD_REGEX_LOWER = /[a-z]/;
const PASSWORD_REGEX_NUMBER = /[0-9]/;

/**
 * Validate domain format
 * @param {string} domain - Domain to validate
 * @param {boolean} allowDeepSubdomains - Whether to allow 3-4 tier subdomains (expert mode)
 * @returns {object} Validation result with { valid: boolean, message?: string }
 */
function validateDomain(domain, allowDeepSubdomains = false) {
  if (!domain) {
    return { valid: false, message: 'Domain is required' };
  }

  // Allow localhost and local domains
  if (domain === 'localhost' || domain.endsWith('.local') || domain.endsWith('.test')) {
    return { valid: true };
  }

  // For expert mode, allow deep subdomains (3-4 levels)
  if (allowDeepSubdomains) {
    // More permissive regex for deep subdomains
    const deepSubdomainRegex = /^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.){0,4}[a-zA-Z]{2,}$/;
    if (!deepSubdomainRegex.test(domain)) {
      return { 
        valid: false, 
        message: 'Invalid domain format. Use format: example.com or app.staging.dev.example.com' 
      };
    }
  } else {
    // Standard validation
    if (!DOMAIN_REGEX.test(domain)) {
      return { 
        valid: false, 
        message: 'Invalid domain format. Use format: example.com or sub.example.com' 
      };
    }
  }

  return { valid: true };
}

/**
 * Validate email format
 * @param {string} email - Email to validate
 * @returns {object} Validation result with { valid: boolean, message?: string }
 */
function validateEmail(email) {
  if (!email) {
    return { valid: false, message: 'Email is required' };
  }

  if (!EMAIL_REGEX.test(email)) {
    return { valid: false, message: 'Invalid email format' };
  }

  return { valid: true };
}

/**
 * Validate password strength
 * @param {string} password - Password to validate
 * @param {boolean} allowEmpty - Whether empty password is allowed (for auto-generation)
 * @returns {object} Validation result with { valid: boolean, message?: string, strength?: string }
 */
function validatePassword(password, allowEmpty = true) {
  if (!password) {
    if (allowEmpty) {
      return { valid: true, message: 'Password will be auto-generated' };
    }
    return { valid: false, message: 'Password is required' };
  }

  const errors = [];
  
  if (password.length < PASSWORD_MIN_LENGTH) {
    errors.push(`at least ${PASSWORD_MIN_LENGTH} characters`);
  }
  
  if (!PASSWORD_REGEX_UPPER.test(password)) {
    errors.push('one uppercase letter');
  }
  
  if (!PASSWORD_REGEX_LOWER.test(password)) {
    errors.push('one lowercase letter');
  }
  
  if (!PASSWORD_REGEX_NUMBER.test(password)) {
    errors.push('one number');
  }

  if (errors.length > 0) {
    return { 
      valid: false, 
      message: `Password must contain ${errors.join(', ')}`
    };
  }

  // Calculate strength
  let strength = 'weak';
  if (password.length >= 12) {
    strength = 'strong';
  } else if (password.length >= 10) {
    strength = 'medium';
  }

  // Check for special characters for extra strength
  if (/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
    strength = strength === 'weak' ? 'medium' : 'strong';
  }

  return { valid: true, strength };
}

/**
 * Validate Cloudflare API token format
 * @param {string} token - Token to validate
 * @returns {object} Validation result
 */
function validateCloudflareToken(token) {
  if (!token) {
    return { valid: false, message: 'Cloudflare API token is required' };
  }

  // Cloudflare tokens are typically 40 characters
  if (token.length < 20) {
    return { valid: false, message: 'Invalid Cloudflare API token format' };
  }

  return { valid: true };
}

/**
 * Validate admin name
 * @param {string} name - Name to validate
 * @returns {object} Validation result
 */
function validateAdminName(name) {
  if (!name) {
    return { valid: false, message: 'Admin name is required' };
  }

  if (name.length < 2) {
    return { valid: false, message: 'Name must be at least 2 characters' };
  }

  if (name.length > 50) {
    return { valid: false, message: 'Name must be less than 50 characters' };
  }

  // Allow letters, spaces, hyphens, and apostrophes
  if (!/^[a-zA-Z\s\-']+$/.test(name)) {
    return { valid: false, message: 'Name can only contain letters, spaces, hyphens, and apostrophes' };
  }

  return { valid: true };
}

/**
 * Validate URL format
 * @param {string} url - URL to validate
 * @returns {object} Validation result
 */
function validateUrl(url) {
  if (!url) {
    return { valid: false, message: 'URL is required' };
  }

  try {
    const urlObj = new URL(url.startsWith('http') ? url : `http://${url}`);
    return { valid: true };
  } catch (e) {
    return { valid: false, message: 'Invalid URL format' };
  }
}

/**
 * Validate service URL (subdomain.domain format)
 * @param {string} serviceUrl - Service URL to validate
 * @returns {object} Validation result
 */
function validateServiceUrl(serviceUrl) {
  if (!serviceUrl) {
    return { valid: false, message: 'Service URL is required' };
  }

  // Allow localhost:port format
  if (/^localhost(:\d+)?$/.test(serviceUrl)) {
    return { valid: true };
  }

  // Check subdomain.domain format
  const parts = serviceUrl.split('.');
  if (parts.length < 2) {
    return { valid: false, message: 'Service URL must be in format: service.domain.com' };
  }

  // Validate as domain
  return validateDomain(serviceUrl);
}

// Export for CommonJS
module.exports = {
  validateDomain,
  validateEmail,
  validatePassword,
  validateCloudflareToken,
  validateAdminName,
  validateUrl,
  validateServiceUrl,
  DOMAIN_REGEX,
  EMAIL_REGEX,
  PASSWORD_MIN_LENGTH
};