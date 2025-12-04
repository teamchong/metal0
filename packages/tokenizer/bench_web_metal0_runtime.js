#!/usr/bin/env node
// metal0 WASM benchmark using @metal0/wasm-runtime
import { readFileSync } from 'fs';
import { load } from '../../packages/wasm-runtime/index.js';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

// Load WASM using generic runtime
const wasmBinary = readFileSync('dist/metal0_tokenizer.wasm');
const mod = await load(wasmBinary);

// Initialize tokenizer with vocab (runtime handles string marshalling)
const vocabData = readFileSync('dist/cl100k_base_full.json', 'utf-8');
const initResult = mod.initFromData(vocabData);
if (initResult < 0) {
    throw new Error(`Failed to initialize tokenizer: ${initResult}`);
}

// Warmup
for (const text of texts.slice(0, 10)) {
    mod.encode(text);
}

// Benchmark: encode all texts 200 times
const start = Date.now();
for (let i = 0; i < 200; i++) {
    for (const text of texts) {
        mod.encode(text);
    }
}
const elapsed = Date.now() - start;

console.log(`metal0 (wasm-runtime): ${elapsed}ms`);
