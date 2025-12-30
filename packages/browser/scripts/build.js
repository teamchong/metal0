#!/usr/bin/env node
/**
 * Build script for lanceql npm package.
 * Bundles the JavaScript module and copies necessary files.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const srcDir = path.join(__dirname, '..', 'src');
const distDir = path.join(__dirname, '..', 'dist');

// Ensure dist directory exists
if (!fs.existsSync(distDir)) {
    fs.mkdirSync(distDir, { recursive: true });
}

// Read the source file
const srcFile = path.join(srcDir, 'lanceql.js');
let content = fs.readFileSync(srcFile, 'utf8');

// Create ESM version (already uses export)
const esmContent = content;
fs.writeFileSync(path.join(distDir, 'lanceql.esm.js'), esmContent);
console.log('Created: dist/lanceql.esm.js');

// Find all named exports
const namedExports = [];
const constMatches = content.matchAll(/^export\s+const\s+(\w+)\s*=/gm);
for (const match of constMatches) namedExports.push(match[1]);

const classMatches = content.matchAll(/^export\s+class\s+(\w+)/gm);
for (const match of classMatches) namedExports.push(match[1]);

const funcMatches = content.matchAll(/^export\s+(?:async\s+)?function\s+(\w+)/gm);
for (const match of funcMatches) namedExports.push(match[1]);

console.log(`Found ${namedExports.length} named exports: ${namedExports.join(', ')}`);

// Create CJS version - remove export keywords
let cjsContent = content
    .replace(/^export\s+const\s+(\w+)\s*=/gm, 'const $1 =')
    .replace(/^export\s+class\s+(\w+)/gm, 'class $1')
    .replace(/^export\s+async\s+function\s+(\w+)/gm, 'async function $1')
    .replace(/^export\s+function\s+(\w+)/gm, 'function $1')
    .replace(/^export\s+default\s+(\w+);?$/gm, '// default export: $1')
    .replace(/^export\s+\{[^}]+\};?$/gm, '');  // Remove named export blocks

// Add module.exports at the end
cjsContent += '\n\n// CommonJS exports\n';
cjsContent += 'module.exports = {\n';
for (const name of namedExports) {
    cjsContent += `    ${name},\n`;
}
cjsContent += `    default: LanceQL\n`;
cjsContent += '};\n';

fs.writeFileSync(path.join(distDir, 'lanceql.js'), cjsContent);
console.log('Created: dist/lanceql.js');

// Copy TypeScript definitions
const dtsFile = path.join(srcDir, 'lanceql.d.ts');
if (fs.existsSync(dtsFile)) {
    fs.copyFileSync(dtsFile, path.join(distDir, 'lanceql.d.ts'));
    console.log('Created: dist/lanceql.d.ts');
}

console.log('Build complete!');
