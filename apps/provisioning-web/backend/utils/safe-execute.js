const { spawn } = require('child_process');

/**
 * Safely execute commands without shell interpretation
 * Prevents command injection by using spawn with array arguments
 * 
 * @param {string} command - The command to execute
 * @param {string[]} args - Array of arguments (safely escaped)
 * @param {object} options - Spawn options
 * @returns {Promise<{stdout: string, stderr: string}>}
 */
function safeExecute(command, args = [], options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      shell: false // Explicitly disable shell
    });
    
    let stdout = '';
    let stderr = '';
    
    // Capture stdout
    if (child.stdout) {
      child.stdout.on('data', (data) => {
        stdout += data.toString();
      });
    }
    
    // Capture stderr
    if (child.stderr) {
      child.stderr.on('data', (data) => {
        stderr += data.toString();
      });
    }
    
    // Handle process completion
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr, code });
      } else {
        const error = new Error(`Process exited with code ${code}`);
        error.code = code;
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      }
    });
    
    // Handle process errors
    child.on('error', (error) => {
      error.stdout = stdout;
      error.stderr = stderr;
      reject(error);
    });
  });
}

/**
 * Validate that a value contains no shell metacharacters
 * Additional safety check for paranoid validation
 * 
 * @param {string} value - Value to check
 * @returns {boolean} - True if safe, false if contains dangerous characters
 */
function isSafeValue(value) {
  // Check for common shell metacharacters
  const dangerousChars = /[;&|`$()<>\[\]{}*?!~\n\r]/;
  return !dangerousChars.test(value);
}

/**
 * Sanitize a value by removing potentially dangerous characters
 * Use only when you must accept user input that might contain special chars
 * 
 * @param {string} value - Value to sanitize
 * @returns {string} - Sanitized value
 */
function sanitizeValue(value) {
  // Remove dangerous characters, keep only safe ones
  return value.replace(/[^a-zA-Z0-9._@\-\/: ]/g, '');
}

module.exports = {
  safeExecute,
  isSafeValue,
  sanitizeValue
};