# Backend Dependencies Documentation

## Philosophy: Minimal Dependencies

The Stack Masters provisioning wizard follows a "minimal dependencies" approach to ensure:
- Fast installation (~20 seconds vs ~60 seconds)
- Reduced security surface area
- Better reliability (fewer things to break)
- Easier maintenance

## Core Dependencies (5 packages)

### 1. express (^4.18.2)
**Purpose**: Web framework
**Why needed**: Core HTTP server functionality
**Cannot remove**: Essential for the web interface

### 2. cookie-parser (^1.4.7)
**Purpose**: Parse and handle cookies
**Why needed**: Security token management
**Cannot remove**: Required for secure session handling

### 3. helmet (^8.1.0)
**Purpose**: Security headers
**Why needed**: Sets various HTTP headers to secure the app
**Cannot remove**: Critical security component

### 4. express-rate-limit (^8.0.1)
**Purpose**: Rate limiting middleware
**Why needed**: Prevents abuse during setup
**Cannot remove**: Security requirement

### 5. ws (^8.14.2)
**Purpose**: WebSocket support
**Why needed**: Real-time deployment progress updates
**Cannot remove**: Core functionality for live updates

## Removed Dependencies

### body-parser ❌
**Reason**: Built into Express 4.16+
**Replacement**: `app.use(express.json())`

### cors ❌
**Reason**: Custom headers in our security module
**Replacement**: Helmet handles necessary headers

### dotenv ❌
**Reason**: Environment handled by setup scripts
**Replacement**: Direct process.env usage

### uuid ❌
**Reason**: Native crypto module has randomUUID()
**Replacement**: `crypto.randomUUID()`

### proper-lockfile ❌
**Reason**: Simplified locking mechanism
**Replacement**: Basic file-based locks

## Installation Performance

### Before Optimization
- Dependencies: 11 packages
- Install time: 45-60 seconds
- Total size: ~25MB

### After Optimization
- Dependencies: 5 packages
- Install time: 15-20 seconds
- Total size: ~8MB

## Code Migration Guide

### 1. Body Parser
```javascript
// OLD
const bodyParser = require('body-parser');
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// NEW
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
```

### 2. UUID Generation
```javascript
// OLD
const { v4: uuidv4 } = require('uuid');
const id = uuidv4();

// NEW
const crypto = require('crypto');
const id = crypto.randomUUID();
```

### 3. Environment Variables
```javascript
// OLD
require('dotenv').config();
const port = process.env.PORT;

// NEW (no dotenv needed)
const port = process.env.PORT;
```

## Security Considerations

Despite fewer dependencies, security is maintained through:
- Helmet for security headers
- Rate limiting for abuse prevention
- Cookie security with httpOnly and secure flags
- Custom input validation
- Platform-specific security measures

## Maintenance

When adding new dependencies:
1. Question if it's truly needed
2. Check if Node.js has built-in alternatives
3. Evaluate the dependency tree size
4. Consider security implications
5. Update this documentation

## Testing Minimal Setup

```bash
# Clean test
rm -rf node_modules package-lock.json
npm install --production
time npm install --production # Should be <20 seconds
```