/**
 * Import shared validators for frontend use
 * This wraps the shared validators module for use in React
 */

// Import the shared validators
import * as sharedValidators from '../../../shared/validators';

// Re-export all validators
export const {
  validateDomain,
  validateEmail,
  validatePassword,
  validateCloudflareToken,
  validateAdminName,
  validateUrl,
  validateServiceUrl
} = sharedValidators;

// Convenience function for form validation
export function validateFormField(fieldName, value, options = {}) {
  switch (fieldName) {
    case 'adminEmail':
      return validateEmail(value);
    
    case 'domain':
      return validateDomain(value);
      
    case 'adminPassword':
      return validatePassword(value, options.allowEmpty);
      
    case 'adminName':
      return validateAdminName(value);
      
    case 'cloudflareToken':
      return validateCloudflareToken(value);
      
    case 'stackManagerUrl':
    case 'n8nUrl':
    case 'grafanaUrl':
      return validateServiceUrl(value);
      
    default:
      return { valid: true };
  }
}

// Helper to get CSS class based on validation
export function getValidationClass(fieldName, value, errors = {}) {
  if (errors[fieldName]) {
    return 'error';
  }
  
  if (!value) {
    return '';
  }
  
  const result = validateFormField(fieldName, value);
  return result.valid ? 'valid' : 'error';
}

// Helper to get validation message
export function getValidationMessage(fieldName, value, options = {}) {
  if (!value && !options.showEmpty) {
    return '';
  }
  
  const result = validateFormField(fieldName, value, options);
  return result.message || '';
}