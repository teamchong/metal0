#!/usr/bin/env node

/**
 * Post-install script for @lanceql/node
 *
 * Attempts to:
 * 1. Copy prebuilt native library if available
 * 2. Fall back to building from source if needed
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PLATFORM = process.platform;
const ARCH = process.arch;

// Map Node.js platform/arch to our prebuild names
const PLATFORM_MAP = {
  darwin: 'darwin',
  linux: 'linux',
  win32: 'win32',
};

const ARCH_MAP = {
  x64: 'x64',
  arm64: 'arm64',
};

// Library file names per platform
const LIB_NAMES = {
  darwin: 'liblanceql.dylib',
  linux: 'liblanceql.so',
  win32: 'lanceql.dll',
};

function getPrebuildPath() {
  const platform = PLATFORM_MAP[PLATFORM];
  const arch = ARCH_MAP[ARCH];

  if (!platform || !arch) {
    return null;
  }

  const prebuildDir = `${platform}-${arch}`;
  const libName = LIB_NAMES[PLATFORM];

  // Check in prebuilds directory
  const prebuildPath = path.join(__dirname, '..', 'prebuilds', prebuildDir, libName);
  if (fs.existsSync(prebuildPath)) {
    return prebuildPath;
  }

  return null;
}

function copyPrebuild(prebuildPath) {
  const libDir = path.join(__dirname, '..', 'lib');
  const libName = LIB_NAMES[PLATFORM];
  const destPath = path.join(libDir, libName);

  // Create lib directory
  if (!fs.existsSync(libDir)) {
    fs.mkdirSync(libDir, { recursive: true });
  }

  // Copy prebuild
  fs.copyFileSync(prebuildPath, destPath);
  console.log(`Copied prebuilt library to ${destPath}`);
  return true;
}

function buildFromSource() {
  console.log('Building from source...');
  try {
    execSync('node-gyp rebuild', { stdio: 'inherit', cwd: path.join(__dirname, '..') });
    return true;
  } catch (err) {
    console.error('Failed to build from source:', err.message);
    return false;
  }
}

function main() {
  console.log(`@lanceql/node install: ${PLATFORM}-${ARCH}`);

  // Try prebuilt first
  const prebuildPath = getPrebuildPath();
  if (prebuildPath) {
    console.log(`Found prebuilt library: ${prebuildPath}`);
    if (copyPrebuild(prebuildPath)) {
      // Still need to build the Node.js addon
      return buildFromSource();
    }
  }

  // Fall back to full source build
  console.log('No prebuilt library found, building from source...');
  return buildFromSource();
}

// Run
if (main()) {
  console.log('@lanceql/node installed successfully');
  process.exit(0);
} else {
  console.error('@lanceql/node installation failed');
  process.exit(1);
}
