# AI Stack Masters Provisioning Wizard - UI Replacement Instructions

## Task Overview
Replace the original wizard UI with this improved UI while keeping the same directory structure and all existing working backend functionality.

## Directory Structure to Maintain
```
apps/provisioning-web/
├── backend/                    # KEEP ALL - Working backend
│   ├── server-integrated.js   # KEEP - Working deployment server
│   ├── validators.js           # KEEP - Working validation
│   ├── url-validator.js        # KEEP - Working URL validation
│   ├── post-deploy-check.js    # KEEP - Working verification
│   ├── encryption-integration.js # KEEP - Working encryption
│   ├── edition-manager.js      # KEEP - Working edition management
│   └── ui-wizard.html          # REPLACE - Old UI file
├── frontend/                   # REPLACE ENTIRE DIRECTORY
│   ├── src/
│   │   ├── App.jsx            # NEW - Improved React UI
│   │   ├── App.css            # NEW - Modern styling
│   │   └── assets/            # NEW - Updated branding
│   ├── package.json           # NEW - Updated dependencies
│   ├── vite.config.js         # NEW - Vite configuration
│   └── index.html             # NEW - Updated HTML
└── README.md                  # UPDATE - Document changes
```

## What to Replace

### ✅ Replace Frontend Completely
- **DELETE**: `apps/provisioning-web/frontend/` (entire directory)
- **COPY**: New React frontend from this project
- **UPDATE**: `backend/server-integrated.js` to serve new React app instead of old HTML

### ✅ Replace Backend UI File
- **DELETE**: `backend/ui-wizard.html` (old HTML interface)
- **KEEP**: All other backend files (they have working functionality)

### ✅ Update Server Configuration
```javascript
// In backend/server-integrated.js
// CHANGE: Static file serving from old HTML to new React build
app.use(express.static(path.join(__dirname, '../frontend/dist')));

// CHANGE: Main route to serve React app
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../frontend/dist/index.html'));
});
```

## Integration Tasks

### 🔧 Connect New UI to Existing Backend APIs

#### 1. Replace Mock Data with Real API Calls
```javascript
// NEW UI currently has mock data - connect to existing APIs
const startDeployment = async (config) => {
  const response = await fetch('/api/deploy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config)
  });
  return response.json();
};
```

#### 2. Connect WebSocket for Real-time Progress
```javascript
// Connect to existing WebSocket endpoint
const ws = new WebSocket(`ws://${window.location.host}`);
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  // Update deployment progress in new UI
};
```

#### 3. Use Existing Validation Functions
```javascript
// Connect form validation to existing backend validators
const validateDomain = async (domain) => {
  const response = await fetch('/api/validate-domain', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ domain })
  });
  return response.json();
};
```

## Existing Working Backend APIs (DO NOT CHANGE)

### ✅ Deployment APIs (Working)
- `POST /api/deploy` - Start real deployment with install.sh
- `GET /api/deploy/:id/status` - Get real deployment status
- `POST /api/deploy/:id/retry/:step` - Retry failed deployment step
- WebSocket `/ws` - Real-time deployment progress

### ✅ Validation APIs (Working)
- `POST /api/validate-domain` - Real domain validation with DNS
- `POST /api/validate-cloudflare` - Real Cloudflare credential validation
- `POST /api/validate-urls` - Real URL validation and checking

### ✅ Export APIs (Working)
- `GET /api/export/logs/:id` - Export real deployment logs
- `GET /api/export/config/:id` - Export real configuration files
- `GET /api/export/diagnostics/:id` - Export system diagnostics

## Step-by-Step Replacement Process

### 1. Backup Original
```bash
cp -r apps/provisioning-web apps/provisioning-web-backup
```

### 2. Replace Frontend
```bash
# Delete old frontend
rm -rf apps/provisioning-web/frontend

# Copy new frontend
cp -r provisioning-wizard-improved apps/provisioning-web/frontend

# Remove git files from copied frontend
rm -rf apps/provisioning-web/frontend/.git
```

### 3. Update Backend Server
```javascript
// In apps/provisioning-web/backend/server-integrated.js
// Update static file serving to point to new React build
app.use(express.static(path.join(__dirname, '../frontend/dist')));
```

### 4. Remove Old UI File
```bash
rm apps/provisioning-web/backend/ui-wizard.html
```

### 5. Build and Test
```bash
cd apps/provisioning-web/frontend
npm install
npm run build

cd ../backend
npm start
```

## Testing Checklist

- [ ] New React UI loads correctly
- [ ] All existing backend APIs still work
- [ ] Form validation connects to existing validators
- [ ] Deployment starts real install.sh process
- [ ] WebSocket shows real-time progress
- [ ] Retry functionality works with existing backend
- [ ] Export buttons download real files
- [ ] Cloudflare configuration works with existing integration
- [ ] Complete deployment flow works end-to-end

## Important Notes

- **KEEP ALL BACKEND FUNCTIONALITY** - It's fully working
- **ONLY REPLACE THE UI** - Frontend and old HTML file
- **MAINTAIN SAME DIRECTORY STRUCTURE** - Don't change paths
- **CONNECT TO EXISTING APIs** - Don't rebuild backend functionality
- **TEST THOROUGHLY** - Ensure all existing features still work

The goal is to have the same working provisioning app with a much better UI/UX experience.

