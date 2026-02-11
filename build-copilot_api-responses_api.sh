#!/bin/bash

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
