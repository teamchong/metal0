#!/usr/bin/env node
// @anthropic-ai/tokenizer benchmark (realistic corpus)
import { countTokens } from '@anthropic-ai/tokenizer';
import { readFileSync } from 'fs';

// Load realistic benchmark data
const data = JSON.parse(readFileSync('benchmark_data.json', 'utf-8'));
const texts = data.texts;

// Warmup
for (const text of texts.slice(0, 10)) {
    countTokens(text);
}

// Benchmark: encode all texts 100 times
const start = Date.now();
for (let i = 0; i < 1000; i++) {
    for (const text of texts) {
        countTokens(text);
    }
}
const elapsed = Date.now() - start;

console.log(`${elapsed}ms`);
