# Provisioning Wizard Build Instructions

## Overview

The Stack Masters Provisioning Wizard frontend is pre-built and committed to the repository to ensure a zero-build installation experience for users. This document explains how to build the frontend when making changes.

## Why Pre-built?

- **Zero Build Time**: Users don't need Node.js or wait for React compilation
- **No Build Failures**: Eliminates npm/node version conflicts for end users
- **WordPress-like Experience**: Instant start, just like WordPress installers
- **Predictable**: Every user gets the exact same frontend assets

## Build Requirements

- Node.js 18+ (LTS recommended)
- pnpm (preferred) or npm

## Build Process

### Linux/macOS
```bash
cd apps/provisioning-web
./build-frontend.sh
```

### Windows
```powershell
cd apps\provisioning-web
.\build-frontend.ps1
```

## What the Build Does

1. Installs frontend dependencies
2. Runs Vite production build
3. Creates optimized assets in `frontend/dist/`
4. The dist folder includes:
   - Minified JavaScript bundles
   - Optimized CSS
   - Static assets (images, fonts)
   - index.html entry point

## Important Notes

### When to Rebuild

You MUST rebuild and commit the dist folder when:
- Making any changes to frontend source code
- Updating dependencies in package.json
- Changing Vite configuration
- Modifying public assets

### Committing the Build

1. Run the build script
2. Test the production build locally
3. Commit the entire `frontend/dist/` folder:
   ```bash
   git add frontend/dist/
   git commit -m "Build: Update frontend production bundle"
   ```

### Testing the Build

After building, test the production version:
```bash
cd backend
NODE_ENV=production node server-integrated.js
```

Then access http://localhost:8080 and verify all functionality works correctly.

## Build Output Structure

```
frontend/dist/
├── index.html          # Entry point
├── assets/
│   ├── index-[hash].js # Main JavaScript bundle
│   ├── index-[hash].css # Main CSS bundle
│   └── ...             # Other assets
└── favicon.ico         # Site icon
```

## Troubleshooting

### Build Fails
- Ensure Node.js 18+ is installed
- Clear node_modules and reinstall: `rm -rf node_modules && pnpm install`
- Check for TypeScript/ESLint errors: `pnpm run lint`

### Large Bundle Size
- Review dependencies - remove unused packages
- Use dynamic imports for large components
- Optimize images before building

### Missing Assets
- Ensure all assets are in `public/` or imported in source
- Check Vite configuration for asset handling