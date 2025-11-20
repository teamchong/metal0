import * as tiktoken from 'tiktoken';

// Expose tiktoken module to window for WASM access
window.tiktokenModule = tiktoken;

let encoder = null;

window.initTiktoken = async function() {
    try {
        // Load WASM manually if window.tiktokenWasmURL is available
        if (window.tiktokenWasmURL && !window.tiktokenWasmLoaded) {
            const response = await fetch(window.tiktokenWasmURL);
            const wasmBytes = await response.arrayBuffer();
            // Collect all __wbindgen_ and __wbg_ functions from tiktoken module
            const imports = {};
            for (const key of Object.keys(tiktoken)) {
                if (key.startsWith('__wbindgen_') || key.startsWith('__wbg_')) {
                    imports[key] = tiktoken[key];
                }
            }
            console.log('WASM imports found:', Object.keys(imports).length);

            const wasmModule = await WebAssembly.instantiate(wasmBytes, {
                './tiktoken_bg.js': imports
            });
            if (tiktoken.__wbg_set_wasm) {
                tiktoken.__wbg_set_wasm(wasmModule.instance.exports);
            }
            window.tiktokenWasmLoaded = true;
            console.log('Tiktoken WASM manually loaded');
        }

        encoder = tiktoken.get_encoding('cl100k_base');
        console.log('tiktoken initialized, tokens:', encoder.encode('test').length);
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
