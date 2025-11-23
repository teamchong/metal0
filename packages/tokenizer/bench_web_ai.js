#!/usr/bin/env node
// @anthropic-ai/tokenizer benchmark (realistic corpus)
import { getTokenizer } from '@anthropic-ai/tokenizer';
import { readFileSync } from 'fs';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

// Initialize tokenizer once (reuse for all calls)
const tokenizer = await getTokenizer();

// Warmup
for (const text of texts.slice(0, 10)) {
    tokenizer.encode(text);
}

// Benchmark: encode all texts 100 times (reduced for slower JS libs)
const start = Date.now();
for (let i = 0; i < 300; i++) {
    for (const text of texts) {
        tokenizer.encode(text);
    }
}
const elapsed = Date.now() - start;

console.log(`${elapsed}ms`);
