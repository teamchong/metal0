#!/usr/bin/env node
// tiktoken (Node.js) benchmark (realistic corpus)
import tiktoken from 'tiktoken';
import { readFileSync } from 'fs';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

const enc = tiktoken.get_encoding('cl100k_base');

// Warmup
for (const text of texts.slice(0, 10)) {
    enc.encode(text);
}

// Benchmark: encode all texts 100 times
const start = Date.now();
for (let i = 0; i < 1000; i++) {
    for (const text of texts) {
        enc.encode(text);
    }
}
const elapsed = Date.now() - start;

enc.free();
console.log(`${elapsed}ms`);
