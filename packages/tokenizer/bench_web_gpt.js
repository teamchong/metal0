#!/usr/bin/env node
// gpt-tokenizer benchmark (realistic corpus)
import { encode } from 'gpt-tokenizer';
import { readFileSync } from 'fs';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

// Warmup
for (const text of texts.slice(0, 10)) {
    encode(text);
}

// Benchmark: encode all texts 100 times
const start = Date.now();
for (let i = 0; i < 300; i++) {
    for (const text of texts) {
        encode(text);
    }
}
const elapsed = Date.now() - start;

console.log(`${elapsed}ms`);
