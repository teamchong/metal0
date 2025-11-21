#!/usr/bin/env node
// PyAOT WASM benchmark (realistic corpus)
import { readFileSync } from 'fs';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

// Load WASM
const wasmBinary = readFileSync('dist/pyaot_tokenizer.wasm');
const wasmModule = await WebAssembly.compile(wasmBinary);

// Create WASM memory
const memory = new WebAssembly.Memory({ initial: 256, maximum: 512 });

const wasmInstance = await WebAssembly.instantiate(wasmModule, {
    env: { memory }
});

const { encode, initFromData, alloc, dealloc } = wasmInstance.exports;

// Load vocab
const vocabData = readFileSync('dist/cl100k_simple.json', 'utf-8');
const vocabBytes = new TextEncoder().encode(vocabData);

// Copy vocab to WASM memory
const vocabPtr = alloc(vocabBytes.length);
const memView = new Uint8Array(memory.buffer);
memView.set(vocabBytes, vocabPtr);

// Initialize tokenizer
const initResult = initFromData(vocabPtr, vocabBytes.length);
if (initResult < 0) {
    throw new Error(`Failed to initialize tokenizer: ${initResult}`);
}

// Warmup
for (const text of texts.slice(0, 10)) {
    const textBytes = new TextEncoder().encode(text);
    const textPtr = alloc(textBytes.length);
    memView.set(textBytes, textPtr);

    const outLen = new Uint32Array(memory.buffer, 0, 1);
    encode(textPtr, textBytes.length, 0);

    dealloc(textPtr, textBytes.length);
}

// Benchmark: encode all texts 100 times
const start = Date.now();
for (let i = 0; i < 1000; i++) {
    for (const text of texts) {
        const textBytes = new TextEncoder().encode(text);
        const textPtr = alloc(textBytes.length);
        memView.set(textBytes, textPtr);

        const outLen = new Uint32Array(memory.buffer, 0, 1);
        encode(textPtr, textBytes.length, 0);

        dealloc(textPtr, textBytes.length);
    }
}
const elapsed = Date.now() - start;

console.log(`${elapsed}ms`);
