const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');

class ProvisioningSecurity {
  constructor() {
    this.setupToken = process.env.SETUP_TOKEN || this.generateSetupToken();
    this.tokenExpiry = Date.now() + (30 * 60 * 1000); // 30 minutes
    this.startTime = Date.now();
    this.lastActivity = Date.now();
    
    this.displaySetupInstructions();
  }

  generateSetupToken() {
    // Increased from 16 to 32 bytes for 256-bit security
    return crypto.randomBytes(32).toString('hex');
  }

  displaySetupInstructions() {
    const boxWidth = 60;
    const separator = '═'.repeat(boxWidth);
    
    console.log('\n');
    console.log('╔' + separator + '╗');
    console.log('║' + ' '.repeat(18) + '🔐 SETUP REQUIRED 🔐' + ' '.repeat(19) + '║');
    console.log('╠' + separator + '╣');
    console.log('║' + ' '.repeat(boxWidth) + '║');
    console.log('║' + this.centerText(`Token: ${this.setupToken}`, boxWidth) + '║');
    console.log('║' + ' '.repeat(boxWidth) + '║');
    console.log('║' + this.centerText('Access your server at:', boxWidth) + '║');
    console.log('║' + this.centerText(`http://YOUR-SERVER-IP/?token=${this.setupToken}`, boxWidth) + '║');
    console.log('║' + ' '.repeat(boxWidth) + '║');
    console.log('║' + this.centerText('Token expires in 30 minutes', boxWidth) + '║');
    console.log('║' + this.centerText(`Expires at: ${new Date(this.tokenExpiry).toLocaleString()}`, boxWidth) + '║');
    console.log('╚' + separator + '╝');
    console.log('\n');
    
    // Also log to file for recovery
    require('fs').writeFileSync('/tmp/provisioning-token.txt', 
      `Token: ${this.setupToken}\nExpires: ${new Date(this.tokenExpiry).toISOString()}\n`
    );
  }

  centerText(text, width) {
    const padding = Math.max(0, width - text.length);
    const leftPad = Math.floor(padding / 2);
    const rightPad = padding - leftPad;
    return ' '.repeat(leftPad) + text + ' '.repeat(rightPad);
  }

  validateToken(token) {
    if (!token) {
      return { valid: false, error: 'No token provided' };
    }
    
    if (Date.now() > this.tokenExpiry) {
      return { valid: false, error: 'Token expired. Please restart the provisioning service.' };
    }
    
    if (token !== this.setupToken) {
      return { valid: false, error: 'Invalid token' };
    }
    
    this.lastActivity = Date.now();
    return { valid: true };
  }

  // Middleware for token validation
  requireToken() {
    return (req, res, next) => {
      // Skip auth for health check, CSRF token endpoint, root (for welcome page), and logo
      if (req.path === '/api/health' || req.path === '/api/csrf-token' || 
          (req.path === '/' && req.method === 'GET') || req.path === '/logo.png') {
        return next();
      }
      
      // Get token from query, header, or cookie
      const token = req.query.token || 
                   req.headers['x-setup-token'] || 
                   req.cookies?.setupToken;
      
      const validation = this.validateToken(token);
      
      if (!validation.valid) {
        return res.status(401).json({ 
          error: validation.error,
          setupRequired: true 
        });
      }
      
      // Set cookie for subsequent requests
      if (!req.cookies?.setupToken) {
        res.cookie('setupToken', token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'strict',
          maxAge: 30 * 60 * 1000 // 30 minutes
        });
      }
      
      next();
    };
  }

  // CSRF protection using double-submit cookie
  csrfProtection() {
    return {
      generate: (req, res, next) => {
        if (!req.cookies?.csrfToken) {
          const token = crypto.randomBytes(32).toString('hex');
          res.cookie('csrfToken', token, {
            httpOnly: false, // Must be readable by JS
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            maxAge: 30 * 60 * 1000
          });
          req.csrfToken = token;
        } else {
          req.csrfToken = req.cookies.csrfToken;
        }
        next();
      },
      
      validate: (req, res, next) => {
        // Skip CSRF for GET requests
        if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
          return next();
        }
        
        const cookieToken = req.cookies?.csrfToken;
        const headerToken = req.headers['x-csrf-token'];
        
        if (!cookieToken || !headerToken || cookieToken !== headerToken) {
          return res.status(403).json({ 
            error: 'Invalid or missing CSRF token',
            csrfRequired: true 
          });
        }
        
        next();
      }
    };
  }

  // Rate limiters
  getRateLimiters() {
    // General API rate limit
    const apiLimiter = rateLimit({
      windowMs: 15 * 60 * 1000, // 15 minutes
      max: 50,
      message: 'Too many requests, please try again later',
      standardHeaders: true,
      legacyHeaders: false,
    });

    // Strict limit for deployment operations
    const deployLimiter = rateLimit({
      windowMs: 60 * 60 * 1000, // 1 hour
      max: 3,
      message: 'Too many deployment attempts, please try again later',
      skipSuccessfulRequests: true,
      standardHeaders: true,
      legacyHeaders: false,
    });

    // Very strict for sensitive operations
    const sensitiveLimiter = rateLimit({
      windowMs: 60 * 60 * 1000, // 1 hour  
      max: 10,
      message: 'Too many sensitive operations, please try again later',
    });

    return { apiLimiter, deployLimiter, sensitiveLimiter };
  }

  // Security headers
  getSecurityHeaders() {
    return helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'"], // React needs these
          styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
          imgSrc: ["'self'", "data:", "https:"],
          connectSrc: ["'self'", "ws:", "wss:"],
          fontSrc: ["'self'", "https://fonts.gstatic.com"],
          objectSrc: ["'none'"],
          mediaSrc: ["'self'"],
          frameSrc: ["'none'"],
        },
      },
      crossOriginEmbedderPolicy: false,
    });
  }

  // Idle timeout checker
  startIdleTimer() {
    const IDLE_TIMEOUT = parseInt(process.env.IDLE_TIMEOUT_MINUTES || '60') * 60 * 1000;
    
    setInterval(() => {
      const idleTime = Date.now() - this.lastActivity;
      
      if (idleTime > IDLE_TIMEOUT) {
        console.log(`Idle timeout reached (${IDLE_TIMEOUT / 1000 / 60} minutes). Shutting down...`);
        process.exit(0);
      }
    }, 60000); // Check every minute
  }

  // Shutdown on successful provisioning
  shutdownOnSuccess() {
    if (process.env.SHUTDOWN_ON_SUCCESS === 'true') {
      console.log('Provisioning completed successfully. Shutting down provisioning service...');
      setTimeout(() => {
        process.exit(0);
      }, 5000); // Give time for final responses
    }
  }
}

module.exports = ProvisioningSecurity;