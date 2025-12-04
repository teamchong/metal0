import { readFileSync } from 'fs';

const wasmBinary = readFileSync('dist/metal0_tokenizer.wasm');
const m = new WebAssembly.Memory({initial:256, maximum:1024});
const mod = await WebAssembly.instantiate(await WebAssembly.compile(wasmBinary), {env:{memory:m}});

console.log('WASM exports:', Object.keys(mod.exports));

// Check if alloc exists
if (mod.exports.alloc) {
    console.log('alloc exists, type:', typeof mod.exports.alloc);
}

// Check initFromData
if (mod.exports.initFromData) {
    console.log('initFromData exists, type:', typeof mod.exports.initFromData);
}

// Try calling with small test data
const testData = '{"!": 0}';
const enc = new TextEncoder();
const bytes = enc.encode(testData);

// Allocate buffer
const ptr = mod.exports.alloc(bytes.length + 1);
console.log('Allocated at ptr:', ptr);

// Write data
const view = new Uint8Array(m.buffer, ptr, bytes.length);
view.set(bytes);

console.log('Calling initFromData with ptr:', ptr, 'len:', bytes.length);
const result = mod.exports.initFromData(ptr, bytes.length);
console.log('Result:', result);
