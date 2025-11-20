#!/usr/bin/env node
/**
 * Web/WASM benchmark for hyperfine
 * Tests PyAOT WASM tokenizer performance
 */

const fs = require('fs');
const path = require('path');

const TEXT = "The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow.";

// Load WASM tokenizer
const wasmPath = path.join(__dirname, 'dist', 'tokenizer.wasm');
const wasmBuffer = fs.readFileSync(wasmPath);

// Simple WASM loader
const wasmModule = new WebAssembly.Module(wasmBuffer);
const wasmInstance = new WebAssembly.Instance(wasmModule, {
    env: {
        // Minimal imports for WASM
        memory: new WebAssembly.Memory({ initial: 256 })
    }
});

const { encode } = wasmInstance.exports;

// Warmup
for (let i = 0; i < 100; i++) {
    encode(TEXT);
}

// Benchmark: 60,000 iterations
const iterations = 60000;
const start = Date.now();

for (let i = 0; i < iterations; i++) {
    encode(TEXT);
}

const elapsed = Date.now() - start;
console.log(`${elapsed}ms`);
