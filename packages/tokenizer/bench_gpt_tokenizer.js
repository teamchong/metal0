#!/usr/bin/env node
/**
 * gpt-tokenizer benchmark (Pure JS)
 */
const { encode } = require('gpt-tokenizer');

const TEXT = "The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow.";

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
