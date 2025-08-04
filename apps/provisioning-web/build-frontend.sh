#!/bin/bash
# Build script for pre-compiling the React frontend
# This script should be run before committing to ensure the dist folder is included

set -e

echo "================================================"
echo "Stack Masters Provisioning Wizard Frontend Build"
echo "================================================"
echo ""

# Change to frontend directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "ERROR: Frontend directory not found at $FRONTEND_DIR"
    exit 1
fi

cd "$FRONTEND_DIR"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "ERROR: Node.js is not installed"
    echo "Please install Node.js 18+ to build the frontend"
    exit 1
fi

# Check Node version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "ERROR: Node.js version 18+ is required (found: $(node -v))"
    exit 1
fi

echo "✓ Node.js $(node -v) detected"

# Check if pnpm is installed (as specified in package.json)
if command -v pnpm &> /dev/null; then
    echo "✓ pnpm detected, using pnpm"
    PKG_MANAGER="pnpm"
elif command -v npm &> /dev/null; then
    echo "✓ npm detected, using npm"
    PKG_MANAGER="npm"
else
    echo "ERROR: No package manager found (pnpm or npm required)"
    exit 1
fi

# Install dependencies
echo ""
echo "Installing dependencies..."
$PKG_MANAGER install

# Run the build
echo ""
echo "Building production bundle..."
$PKG_MANAGER run build

# Check if build was successful
if [ ! -d "dist" ]; then
    echo "ERROR: Build failed - dist directory not created"
    exit 1
fi

# Show build results
echo ""
echo "✅ Build completed successfully!"
echo ""
echo "Build output:"
du -sh dist/
echo ""
ls -la dist/

echo ""
echo "================================================"
echo "IMPORTANT: The dist/ folder has been created."
echo "Make sure to:"
echo "1. Update frontend/.gitignore to NOT ignore dist/"
echo "2. Commit the dist/ folder to the repository"
echo "3. Test the production build locally"
echo "================================================"