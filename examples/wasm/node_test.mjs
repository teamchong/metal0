// Node.js test for metal0 WASM
// Run: node node_test.mjs

import { readFile } from 'fs/promises';

// Immer-style runtime (simplified for Node.js)
async function load(path) {
    const bytes = await readFile(path);
    const w = (await WebAssembly.instantiate(bytes, {})).instance.exports;
    return new Proxy({}, {
        get: (_, n) => typeof w[n] === 'function'
            ? (...a) => w[n](...a.map(v => typeof v === 'number' ? BigInt(v) : v))
            : w[n]
    });
}

// Test the module
console.log('Testing metal0 WASM exports...');
console.log('');

const mod = await load('./math.wasm');

const sum = mod.add(3, 4);
console.log(`add(3, 4) = ${sum}`);
console.assert(Number(sum) === 7, `Expected 7, got ${sum}`);

const product = mod.multiply(5, 6);
console.log(`multiply(5, 6) = ${product}`);
console.assert(Number(product) === 30, `Expected 30, got ${product}`);

const sq = mod.square(8);
console.log(`square(8) = ${sq}`);
console.assert(Number(sq) === 64, `Expected 64, got ${sq}`);

const max = mod.max_of(10, 25);
console.log(`max_of(10, 25) = ${max}`);
console.assert(Number(max) === 25, `Expected 25, got ${max}`);

const abs = mod.abs_val(-42);
console.log(`abs_val(-42) = ${abs}`);
console.assert(Number(abs) === 42, `Expected 42, got ${abs}`);

console.log('');
console.log('All tests passed!');
