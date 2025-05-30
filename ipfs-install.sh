#!/bin/bash

# Script to install IPFS on Debian ARM and move to ~/bin/

# Exit on error
set -e

# Variables
IPFS_VERSION="v0.35.0"  # Latest version as specified
DOWNLOAD_URL="https://dist.ipfs.io/kubo/${IPFS_VERSION}/kubo_${IPFS_VERSION}_linux-arm64.tar.gz"
INSTALL_DIR="$HOME/bin"
TEMP_DIR=$(mktemp -d)

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    echo "Installing wget..."
    sudo apt-get update
    sudo apt-get install -y wget
fi

# Create ~/bin if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Download IPFS
echo "Downloading IPFS ${IPFS_VERSION}..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$TEMP_DIR/ipfs.tar.gz"

# Extract and install
echo "Installing IPFS to ${INSTALL_DIR}..."
tar -xzf "$TEMP_DIR/ipfs.tar.gz" -C "$TEMP_DIR"
mv "$TEMP_DIR/kubo/ipfs" "$INSTALL_DIR/"

# Clean up
rm -rf "$TEMP_DIR"

# Ensure ~/bin is in PATH
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo "Adding ~/bin to PATH..."
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/bin:$PATH"
fi

# Verify installation
if command -v ipfs &> /dev/null; then
    echo "IPFS installed successfully!"
    ipfs --version
else
    echo "Installation failed!"
    exit 1
fi
