import * as tiktoken from 'tiktoken';

let encoder = null;

window.initTiktoken = async function() {
    try {
        console.log('tiktoken:', tiktoken);
        encoder = tiktoken.get_encoding('cl100k_base');
        console.log('tiktoken initialized');
    } catch (e) {
        console.error('tiktoken init error:', e);
        throw e;
    }
};

window.benchTiktoken = function(text, iterations) {
    if (!encoder) throw new Error('Tiktoken not initialized');

    // Warmup
    for (let i = 0; i < 100; i++) encoder.encode(text);

    // Benchmark
    const start = performance.now();
    for (let i = 0; i < iterations; i++) {
        encoder.encode(text);
    }
    return performance.now() - start;
};

window.testTiktoken = function(text) {
    if (!encoder) throw new Error('Tiktoken not initialized');
    return encoder.encode(text).length;
};

window.freeTiktoken = function() {
    if (encoder) encoder.free();
};
