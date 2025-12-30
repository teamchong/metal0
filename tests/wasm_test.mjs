#!/usr/bin/env node
/**
 * WASM Parser Tests
 * 
 * These tests verify that the WASM parser correctly reads Lance v2 files
 * by comparing output against known expected values from Python-generated
 * test fixtures.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = path.join(__dirname, 'fixtures');
const WASM_PATH = path.join(__dirname, '..', 'zig-out', 'bin', 'lanceql.wasm');

// Test results tracking
let passed = 0;
let failed = 0;
const failures = [];

function assert(condition, message) {
    if (condition) {
        passed++;
    } else {
        failed++;
        failures.push(message);
        console.error(`  ✗ ${message}`);
    }
}

function assertArrayEqual(actual, expected, message) {
    if (actual.length !== expected.length) {
        assert(false, `${message}: length mismatch (${actual.length} vs ${expected.length})`);
        return;
    }
    for (let i = 0; i < expected.length; i++) {
        if (actual[i] !== expected[i]) {
            assert(false, `${message}: mismatch at index ${i} (${actual[i]} vs ${expected[i]})`);
            return;
        }
    }
    assert(true, message);
}

function assertFloatArrayEqual(actual, expected, message, tolerance = 1e-6) {
    if (actual.length !== expected.length) {
        assert(false, `${message}: length mismatch (${actual.length} vs ${expected.length})`);
        return;
    }
    for (let i = 0; i < expected.length; i++) {
        if (Math.abs(actual[i] - expected[i]) > tolerance) {
            assert(false, `${message}: mismatch at index ${i} (${actual[i]} vs ${expected[i]})`);
            return;
        }
    }
    assert(true, message);
}

// Load WASM
const wasmBytes = fs.readFileSync(WASM_PATH);
const wasm = new WebAssembly.Instance(new WebAssembly.Module(wasmBytes), {
    env: { log_value: () => {} }
}).exports;

// Helper to load a lance file
function loadLanceFile(datasetPath) {
    const dataDir = path.join(datasetPath, 'data');
    const files = fs.readdirSync(dataDir);
    const lanceFile = files.find(f => f.endsWith('.lance'));
    if (!lanceFile) throw new Error(`No .lance file in ${dataDir}`);
    
    const fileData = fs.readFileSync(path.join(dataDir, lanceFile));
    const ptr = wasm.alloc(fileData.length);
    new Uint8Array(wasm.memory.buffer).set(fileData, ptr);
    
    const result = wasm.openFile(ptr, fileData.length);
    if (result !== 1) throw new Error(`Failed to open ${datasetPath}`);
    
    return { ptr, length: fileData.length };
}

// Helper to read int64 column
function readInt64Column(colIdx, maxRows = 100) {
    const buf = wasm.allocInt64Buffer(maxRows);
    const count = wasm.readInt64Column(colIdx, buf, maxRows);
    const values = new BigInt64Array(wasm.memory.buffer, buf, count);
    return Array.from(values).map(v => Number(v));
}

// Helper to read float64 column
function readFloat64Column(colIdx, maxRows = 100) {
    const buf = wasm.allocFloat64Buffer(maxRows);
    const count = wasm.readFloat64Column(colIdx, buf, maxRows);
    const values = new Float64Array(wasm.memory.buffer, buf, count);
    return Array.from(values);
}

// Helper to read string column
function readStringColumn(colIdx, maxRows = 100) {
    const strings = [];
    const count = Number(wasm.getStringCount(colIdx));
    for (let i = 0; i < Math.min(count, maxRows); i++) {
        const outBuf = wasm.allocStringBuffer(10000);
        const len = wasm.readStringAt(colIdx, i, outBuf, 10000);
        if (len > 0) {
            const str = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, outBuf, len));
            strings.push(str);
        } else {
            strings.push('');
        }
    }
    return strings;
}

// Helper to read vector column
function readVectorColumn(colIdx, maxRows = 100) {
    // getVectorInfo returns packed value: (rows << 32) | dimension
    const packed = wasm.getVectorInfo(colIdx);
    const info = {
        dimension: Number(BigInt(packed) & 0xFFFFFFFFn),
        rows: Number(BigInt(packed) >> 32n)
    };

    const vectors = [];
    for (let i = 0; i < Math.min(info.rows, maxRows); i++) {
        const buf = wasm.allocFloat32Buffer(info.dimension);
        const actualDim = wasm.readVectorAt(colIdx, i, buf, info.dimension);
        if (actualDim > 0) {
            const vec = new Float32Array(wasm.memory.buffer, buf, actualDim);
            vectors.push(Array.from(vec));
        }
    }
    return { info, vectors };
}

// ============================================================================
// TEST: basic_types.lance
// ============================================================================
console.log('\n=== Test: basic_types.lance ===');
{
    loadLanceFile(path.join(FIXTURES_DIR, 'basic_types.lance'));
    
    // Check column count
    const numCols = wasm.getNumColumns();
    assert(numCols === 3, `Column count should be 3, got ${numCols}`);
    
    // Test int64 column (id)
    const ids = readInt64Column(0);
    assertArrayEqual(ids, [0, 1, 2, 3, 4], 'int64 column values');
    
    // Test string column (name)
    const names = readStringColumn(1);
    assertArrayEqual(names, ['alpha', 'beta', 'gamma', 'delta', 'epsilon'], 'string column values');
    
    // Test float64 column (score)
    const scores = readFloat64Column(2);
    assertFloatArrayEqual(scores, [1.5, 2.5, 3.5, 4.5, 5.5], 'float64 column values');
    
    wasm.closeFile();
}

// ============================================================================
// TEST: vectors.lance
// ============================================================================
console.log('\n=== Test: vectors.lance ===');
{
    loadLanceFile(path.join(FIXTURES_DIR, 'vectors.lance'));
    
    const numCols = wasm.getNumColumns();
    assert(numCols === 2, `Column count should be 2, got ${numCols}`);
    
    // Test int64 column (id)
    const ids = readInt64Column(0);
    assertArrayEqual(ids, [0, 1, 2, 3, 4], 'int64 column values');
    
    // Test vector column (embedding)
    const { info, vectors } = readVectorColumn(1);
    assert(info.dimension === 4, `Vector dimension should be 4, got ${info.dimension}`);
    assert(info.rows === 5, `Vector row count should be 5, got ${info.rows}`);
    
    assertFloatArrayEqual(vectors[0], [1.0, 0.0, 0.0, 0.0], 'vector[0] values', 1e-5);
    assertFloatArrayEqual(vectors[1], [0.0, 1.0, 0.0, 0.0], 'vector[1] values', 1e-5);
    assertFloatArrayEqual(vectors[4], [0.5, 0.5, 0.5, 0.5], 'vector[4] values', 1e-5);
    
    wasm.closeFile();
}

// ============================================================================
// TEST: strings_various.lance
// ============================================================================
console.log('\n=== Test: strings_various.lance ===');
{
    loadLanceFile(path.join(FIXTURES_DIR, 'strings_various.lance'));
    
    const numCols = wasm.getNumColumns();
    assert(numCols === 2, `Column count should be 2, got ${numCols}`);
    
    // Test string column with various lengths
    const texts = readStringColumn(1);
    assert(texts[0] === '', 'empty string');
    assert(texts[1] === 'a', 'single char string');
    assert(texts[2] === 'hello', 'normal string');
    assert(texts[3] === 'hello world with spaces', 'string with spaces');
    assert(texts[4] === '你好世界', 'unicode string');
    
    wasm.closeFile();
}

// ============================================================================
// TEST: large.lance
// ============================================================================
console.log('\n=== Test: large.lance ===');
{
    loadLanceFile(path.join(FIXTURES_DIR, 'large.lance'));
    
    const numCols = wasm.getNumColumns();
    assert(numCols === 2, `Column count should be 2, got ${numCols}`);
    
    // Test row count
    const rowCount = Number(wasm.getRowCount(0));
    assert(rowCount === 1000, `Row count should be 1000, got ${rowCount}`);
    
    // Test boundary values
    const ids = readInt64Column(0, 1000);
    assert(ids[0] === 0, 'first id should be 0');
    assert(ids[999] === 999, 'last id should be 999');
    
    const values = readFloat64Column(1, 1000);
    assertFloatArrayEqual([values[0]], [0.0], 'first value', 1e-6);
    assertFloatArrayEqual([values[999]], [99.9], 'last value', 1e-6);
    
    wasm.closeFile();
}

// ============================================================================
// TEST: Manifest parsing (column names)
// ============================================================================
console.log('\n=== Test: Manifest parsing ===');
{
    // Test that we can parse manifest to get column names
    const manifestPath = path.join(FIXTURES_DIR, 'basic_types.lance', '_versions', '1.manifest');
    const manifestData = fs.readFileSync(manifestPath);
    
    // Parse manifest (same logic as in index.html)
    function parseManifestForColumnNames(data) {
        const names = [];
        const protoLen = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
        const protoEnd = 4 + protoLen;
        let pos = 4;

        function readVarint() {
            let result = 0;
            let shift = 0;
            while (pos < data.length) {
                const byte = data[pos++];
                result |= (byte & 0x7f) << shift;
                if ((byte & 0x80) === 0) break;
                shift += 7;
            }
            return result;
        }

        function readString(len) {
            const str = new TextDecoder().decode(data.slice(pos, pos + len));
            pos += len;
            return str;
        }

        function skipField(wireType) {
            if (wireType === 0) readVarint();
            else if (wireType === 1) pos += 8;
            else if (wireType === 2) pos += readVarint();
            else if (wireType === 5) pos += 4;
        }

        while (pos < protoEnd) {
            const tag = readVarint();
            const fieldNum = tag >> 3;
            const wireType = tag & 0x7;

            if (fieldNum === 1 && wireType === 2) {
                const fieldLen = readVarint();
                const fieldEnd = pos + fieldLen;
                let fieldName = null;
                while (pos < fieldEnd) {
                    const fieldTag = readVarint();
                    const fieldFieldNum = fieldTag >> 3;
                    const fieldWireType = fieldTag & 0x7;
                    if (fieldFieldNum === 2 && fieldWireType === 2) {
                        const nameLen = readVarint();
                        fieldName = readString(nameLen);
                    } else {
                        skipField(fieldWireType);
                    }
                }
                if (fieldName) names.push(fieldName);
            } else {
                skipField(wireType);
            }
        }
        return names;
    }
    
    const columnNames = parseManifestForColumnNames(manifestData);
    assertArrayEqual(columnNames, ['id', 'name', 'score'], 'manifest column names');
}

// ============================================================================
// Summary
// ============================================================================
console.log('\n=== Summary ===');
console.log(`Passed: ${passed}`);
console.log(`Failed: ${failed}`);

if (failures.length > 0) {
    console.log('\nFailures:');
    failures.forEach(f => console.log(`  - ${f}`));
    process.exit(1);
} else {
    console.log('\nAll tests passed!');
    process.exit(0);
}
