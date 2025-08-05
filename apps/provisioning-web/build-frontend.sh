#!/bin/bash
# Stack Masters Frontend Build Script for Linux/Mac
# Handles Node.js v23 compatibility issues automatically

echo "========================================"
echo "Stack Masters Frontend Build (Linux/Mac)"
echo "========================================"
echo ""

# Get Node.js version
NODE_VERSION=$(node --version 2>&1)
echo "Node.js version: $NODE_VERSION"

# Check if we're on Node.js v23
IS_NODE_V23=false
if [[ "$NODE_VERSION" == *"v23."* ]]; then
    IS_NODE_V23=true
    echo "Detected Node.js v23 - Using compatibility mode"
fi

# Navigate to frontend directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "[ERROR] Frontend directory not found: $FRONTEND_DIR"
    exit 1
fi

cd "$FRONTEND_DIR"

# Clean install if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    
    if [ "$IS_NODE_V23" = true ]; then
        echo "Using --legacy-peer-deps for Node.js v23 compatibility"
        npm install --legacy-peer-deps
    else
        npm install
    fi
    
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to install dependencies"
        exit 1
    fi
fi

# Build the frontend
echo ""
echo "Building React frontend..."

npm run build

if [ $? -eq 0 ]; then
    echo ""
    echo "[SUCCESS] Frontend built successfully!"
    echo "Build output: $FRONTEND_DIR/dist"
    
    # Copy to backend if needed
    BACKEND_DIST_DIR="$SCRIPT_DIR/backend/frontend/dist"
    PARENT_DIR=$(dirname "$BACKEND_DIST_DIR")
    
    if [ ! -d "$PARENT_DIR" ]; then
        mkdir -p "$PARENT_DIR"
    fi
    
    echo "Copying build to backend directory..."
    cp -r dist "$BACKEND_DIST_DIR"
    echo "[SUCCESS] Frontend deployed to backend!"
else
    echo ""
    echo "[ERROR] Build failed!"
    
    if [ "$IS_NODE_V23" = true ]; then
        echo ""
        echo "Node.js v23 Compatibility Note:"
        echo "The build uses @rollup/wasm-node for cross-platform compatibility."
        echo "If issues persist, consider using Node.js v20 LTS."
    fi
    
    exit 1
fi