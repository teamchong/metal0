/**
 * Basic tests for lanceql npm package.
 * Tests module loading and basic API.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Test that the module can be imported
describe('Module Loading', () => {
    test('ESM module exports are present', async () => {
        const module = await import('../dist/lanceql.esm.js');

        // Check that key exports exist
        // LanceQL is the default export
        assert.ok(module.default !== undefined, 'default export should exist');
        assert.ok(typeof module.default === 'object' || typeof module.default === 'function',
            'LanceQL should be exported as default');
        // LanceData is a named export
        assert.ok(typeof module.LanceData === 'function',
            'LanceData should be exported');
    });

    test('ESM module file exists', () => {
        const esmPath = path.join(__dirname, '..', 'dist', 'lanceql.esm.js');
        assert.ok(fs.existsSync(esmPath), 'ESM module should exist');
    });

    test('WASM file exists', () => {
        const wasmPath = path.join(__dirname, '..', 'dist', 'lanceql.wasm');
        assert.ok(fs.existsSync(wasmPath), 'WASM file should exist');
    });

    test('TypeScript definitions exist', () => {
        const dtsPath = path.join(__dirname, '..', 'dist', 'lanceql.d.ts');
        assert.ok(fs.existsSync(dtsPath), 'TypeScript definitions should exist');
    });
});

describe('Package Structure', () => {
    test('package.json has correct fields', async () => {
        const pkgPath = path.join(__dirname, '..', 'package.json');
        const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));

        assert.strictEqual(pkg.name, 'lanceql');
        assert.ok(pkg.version, 'version should be set');
        assert.ok(pkg.main, 'main should be set');
        assert.ok(pkg.module, 'module should be set');
        assert.ok(pkg.types, 'types should be set');
    });

    test('exports map is correct', async () => {
        const pkgPath = path.join(__dirname, '..', 'package.json');
        const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));

        assert.ok(pkg.exports['.'], 'default export should exist');
        assert.ok(pkg.exports['./wasm'], 'wasm export should exist');
    });
});

describe('LanceData CSS Engine', () => {
    test('LanceData class has expected static methods', async () => {
        const { LanceData } = await import('../dist/lanceql.esm.js');

        assert.ok(typeof LanceData.init === 'function', 'init should be a function');
        assert.ok(typeof LanceData.registerRenderer === 'function', 'registerRenderer should be a function');
        assert.ok(typeof LanceData.clearCache === 'function', 'clearCache should be a function');
        assert.ok(typeof LanceData.refresh === 'function', 'refresh should be a function');
        assert.ok(typeof LanceData.destroy === 'function', 'destroy should be a function');
    });
});
