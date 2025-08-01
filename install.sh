#!/bin/bash
# Stack Manager Quick Installer
# This script downloads and runs the setup script in one command

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   echo "Please run: curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/install.sh | sudo bash"
   exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download setup script
echo "Downloading Stack Masters setup script..."
curl -fsSL https://raw.githubusercontent.com/Tech-to-Thrive/sm-setup/main/setup.sh -o setup.sh

# Make executable
chmod +x setup.sh

# Run setup
echo "Starting Stack Manager setup..."
./setup.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"