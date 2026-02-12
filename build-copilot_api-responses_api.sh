#!/bin/bash
#
# build-copilot_api-responses_api.sh
# 
# This script builds and installs a custom version of copilot-api with the
# responses-api feature branch. It clones the source, modifies the version
# string, builds the project, and installs it globally via npm.
#
# If copilot-api is already installed with the correct version (matching the
# remote feature/responses-api branch), the script skips the installation.
#
# Requirements:
#   - npm (Node.js package manager)
#
# Usage:
#   ./build-copilot_api-responses_api.sh
#

if ! command -v npm &> /dev/null; then
    echo "Warning: npm is not available. Please install Node.js and npm first."
    exit 1
fi

if command -v copilot-api &> /dev/null; then
    INSTALLED_VERSION=$(copilot-api --version 2>/dev/null)
    if [[ "$INSTALLED_VERSION" == *"-responses-api" ]]; then
        BASE_VERSION="${INSTALLED_VERSION%-responses-api}"
        REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/caozhiyuan/copilot-api/feature/responses-api/package.json | grep '"version":' | cut -d'"' -f4)
        if [[ "$BASE_VERSION" == "$REMOTE_VERSION" ]]; then
            echo "copilot-api $INSTALLED_VERSION is already installed and up-to-date. Skipping installation."
            exit 0
        fi
    fi
fi

# Get the pacakge source code
git clone -b feature/responses-api https://github.com/caozhiyuan/copilot-api.git copilot-api
cd copilot-api

# Extract the version (e.g., 0.7.0)
OLD_VERSION=$(grep '"version":' package.json | cut -d'"' -f4)
NEW_VERSION="${OLD_VERSION}-responses-api"

# Apply changes to enable the --version flag and custom naming
sed -i "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" package.json
sed -i "/name: \"copilot-api\",/a \    version: \"$NEW_VERSION\"," src/main.ts

# Install dependencies and build the project
npm install
npx tsdown

# Create a production tarball (bypassing the bun-based prepack script)
npm pack --ignore-scripts

# Install the generated tarball globally
npm install -g ./copilot-api-${NEW_VERSION}.tgz

# Cleanup
cd ..
rm -rf copilot-api
npm cache clean --force
