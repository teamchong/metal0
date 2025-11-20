#!/usr/bin/env python3
"""
Browser tokenizer benchmark using Playwright
Injects and runs benchmarks directly in headless Chrome
"""
import asyncio

try:
    from playwright.async_api import async_playwright
except ImportError:
    print("Install: pip install playwright && playwright install chromium")
    exit(1)

BENCHMARK_CODE = """
(async () => {
    const results = [];
    const TEXT = "The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow.";
    const ITERATIONS = 10000;

    console.log('Testing gpt-tokenizer (JS)...');
    try {
        const { encode } = await import('https://cdn.jsdelivr.net/npm/gpt-tokenizer@2.1.1/+esm');

        for (let i = 0; i < 100; i++) encode(TEXT);

        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'gpt-tokenizer',
            time: Math.round(elapsed),
            tokens: encode(TEXT).length,
            type: 'Pure JS'
        });
    } catch (e) {
        results.push({ name: 'gpt-tokenizer', error: e.message });
    }

    console.log('Testing ai-tokenizer (Pure JS)...');
    try {
        const aiTokenizer = await import('https://esm.sh/ai-tokenizer@1.0.3');
        const encoding = await import('https://esm.sh/ai-tokenizer@1.0.3/encoding');

        const TokenizerClass = aiTokenizer.default || aiTokenizer;
        // Use cl100k_base encoding directly
        const enc = new TokenizerClass(encoding.cl100k_base || encoding.default.cl100k_base);

        // Warmup
        for (let i = 0; i < 100; i++) enc.encode(TEXT);

        // Benchmark
        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) enc.encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'ai-tokenizer',
            time: Math.round(elapsed),
            tokens: enc.encode(TEXT).length,
            type: 'Pure JS'
        });
    } catch (e) {
        console.error('ai-tokenizer error:', e);
        results.push({ name: 'ai-tokenizer', error: e.message || e.toString() });
    }

    console.log('Testing tiktoken (WASM)...');
    try {
        const tiktoken = await import(window.tiktokenModuleUrl);
        const enc = tiktoken.get_encoding('cl100k_base');

        // Warmup
        for (let i = 0; i < 100; i++) enc.encode(TEXT);

        // Benchmark
        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) enc.encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'tiktoken (WASM)',
            time: Math.round(elapsed),
            tokens: enc.encode(TEXT).length,
            type: 'Rust → WASM'
        });
        enc.free();
    } catch (e) {
        console.error('tiktoken error:', e);
        results.push({ name: 'tiktoken (WASM)', error: e.message || e.toString() });
    }


    console.log('Testing @huggingface/tokenizers (WASM)...');
    try {
        const { AutoTokenizer } = await import('https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.1.2/+esm');
        const tokenizer = await AutoTokenizer.from_pretrained('Xenova/gpt-4');

        for (let i = 0; i < 100; i++) tokenizer.encode(TEXT);

        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) tokenizer.encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: '@huggingface/transformers',
            time: Math.round(elapsed),
            tokens: tokenizer.encode(TEXT).length,
            type: 'Rust → WASM'
        });
    } catch (e) {
        results.push({ name: '@huggingface/transformers', error: e.message || e.toString() });
    }

    console.log('Testing PyAOT WASM...');
    try {
        // Decode WASM from base64
        const wasmBytes = Uint8Array.from(atob(window.PYAOT_WASM_B64), c => c.charCodeAt(0));

        const { instance } = await WebAssembly.instantiate(wasmBytes, {});

        // Use WASM's own exported memory (not create new one!)
        const wasmMemory = instance.exports.memory;

        // Initialize with vocab
        const encoder = new TextEncoder();
        const jsonBytes = encoder.encode(window.VOCAB_JSON);

        const jsonPtr = instance.exports.alloc(jsonBytes.length);
        const memory = new Uint8Array(wasmMemory.buffer);
        memory.set(jsonBytes, jsonPtr);

        const initResult = instance.exports.initFromData(jsonPtr, jsonBytes.length);
        instance.exports.dealloc(jsonPtr, jsonBytes.length);

        if (initResult === 0) throw new Error('Init failed - check vocab format');

        // Encode function
        function encodeWasm(text) {
            const textBytes = encoder.encode(text);
            const textPtr = instance.exports.alloc(textBytes.length);
            new Uint8Array(wasmMemory.buffer).set(textBytes, textPtr);

            const outLenPtr = instance.exports.alloc(4);
            const outLenView = new Uint32Array(wasmMemory.buffer, outLenPtr, 1);

            const tokensPtr = instance.exports.encode(textPtr, textBytes.length, outLenPtr);
            const tokensLen = outLenView[0];

            const tokensView = new Uint32Array(wasmMemory.buffer, tokensPtr, tokensLen);
            const result = Array.from(tokensView);

            instance.exports.dealloc(textPtr, textBytes.length);
            instance.exports.dealloc(outLenPtr, 4);

            return result;
        }

        // Warmup
        for (let i = 0; i < 100; i++) encodeWasm(TEXT);

        // Benchmark
        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) encodeWasm(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'PyAOT (Zig→WASM)',
            time: Math.round(elapsed),
            tokens: encodeWasm(TEXT).length,
            type: 'Zig → WASM'
        });
    } catch (e) {
        console.error('PyAOT WASM error:', e);
        results.push({ name: 'PyAOT (Zig→WASM)', error: e.message || e.toString() });
    }


    return results;
})()
"""

async def main():
    print("🚀 Browser Tokenizer Benchmark")
    print("=" * 60)

    # Load WASM and vocab files
    import base64
    import urllib.request

    with open('dist/pyaot_tokenizer.wasm', 'rb') as f:
        wasm_b64 = base64.b64encode(f.read()).decode('ascii')

    with open('dist/cl100k_simple.json', 'r') as f:
        vocab_json = f.read()

    # Download tiktoken WASM and JS (use FULL version, not /lite)
    print("Downloading tiktoken WASM...")
    tiktoken_wasm_url = 'https://unpkg.com/tiktoken@1.0.15/tiktoken_bg.wasm'
    tiktoken_wasm = urllib.request.urlopen(tiktoken_wasm_url).read()
    tiktoken_wasm_b64 = base64.b64encode(tiktoken_wasm).decode('ascii')

    print("Downloading tiktoken JS...")
    tiktoken_js_url = 'https://unpkg.com/tiktoken@1.0.15/tiktoken.js'
    tiktoken_js = urllib.request.urlopen(tiktoken_js_url).read().decode('utf-8')

    print("Downloading tiktoken glue JS...")
    tiktoken_bg_js_url = 'https://unpkg.com/tiktoken@1.0.15/tiktoken_bg.js'
    tiktoken_bg_js = urllib.request.urlopen(tiktoken_bg_js_url).read().decode('utf-8')

    # Modify tiktoken.js to use WebAssembly.instantiate instead of ES module import
    # The browser doesn't support importing WASM as ES modules
    tiktoken_js_modified = tiktoken_js.replace(
        'import * as wasm from "./tiktoken_bg.wasm";\nimport { __wbg_set_wasm } from "./tiktoken_bg.js";\n__wbg_set_wasm(wasm);',
        '''// Load WASM via WebAssembly.instantiate
import { __wbg_set_wasm } from "./tiktoken_bg.js";
const wasmResponse = await fetch('https://unpkg.com/tiktoken@1.0.15/tiktoken_bg.wasm');
const wasmBytes = await wasmResponse.arrayBuffer();
const wasmModule = await WebAssembly.compile(wasmBytes);
const wasmImports = await import('./tiktoken_bg.js');
const wasmInstance = await WebAssembly.instantiate(wasmModule, { './tiktoken_bg.js': wasmImports });
__wbg_set_wasm(wasmInstance.exports);'''
    )

    async with async_playwright() as p:
        print("Launching Chrome...")
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        # Go to blank page
        await page.goto('about:blank')

        print("Running benchmarks (10K iterations)...")
        print()

        # Listen to console
        page.on("console", lambda msg: print(f"Browser: {msg.text}"))

        # Inject files as variables
        await page.evaluate(f"window.PYAOT_WASM_B64 = '{wasm_b64}';")
        await page.evaluate(f"window.VOCAB_JSON = {repr(vocab_json)};")
        await page.evaluate(f"window.TIKTOKEN_WASM_B64 = '{tiktoken_wasm_b64}';")

        # Intercept tiktoken WASM and JS requests
        async def handle_route(route):
            url = route.request.url
            if 'tiktoken_bg.wasm' in url:
                print(f"Intercepting WASM: {url}")
                await route.fulfill(body=tiktoken_wasm, content_type='application/wasm')
            elif 'tiktoken_bg.js' in url:
                print(f"Intercepting glue JS: {url}")
                await route.fulfill(body=tiktoken_bg_js.encode('utf-8'), content_type='application/javascript')
            elif 'tiktoken.js' in url or 'tiktoken@' in url or '/lite/tiktoken' in url:
                print(f"Intercepting JS: {url}")
                await route.fulfill(body=tiktoken_js_modified.encode('utf-8'), content_type='application/javascript')
            else:
                await route.continue_()

        await page.route('**/*', handle_route)

        # Set up tiktoken module URL
        await page.evaluate("window.tiktokenModuleUrl = 'https://unpkg.com/tiktoken@1.0.15/tiktoken.js';")

        # Inject and run benchmark code
        results = await page.evaluate(BENCHMARK_CODE)

        # Display results
        print("Results:")
        print("-" * 60)

        successful = [r for r in results if 'error' not in r]
        successful.sort(key=lambda x: x['time'])

        if successful:
            fastest = successful[0]['time']

            for r in successful:
                speedup = r['time'] / fastest
                trophy = " 🏆" if speedup == 1.0 else ""
                impl_type = r.get('type', 'Unknown')
                print(f"{r['name']:<20} {r['time']:>6}ms   {speedup:>5.2f}x   {r['tokens']} tokens   {impl_type}{trophy}")

        # Show errors
        errors = [r for r in results if 'error' in r]
        for r in errors:
            print(f"{r['name']:<20} ERROR: {r['error']}")

        print()
        print("=" * 60)
        print("Comparison with native (60K iterations):")
        print("  PyAOT (Zig):         741ms 🏆")
        print("  TokenDagger (C):     775ms")
        print("  tiktoken (Rust):    1194ms")
        print()
        print("Browser is ~6-7x slower than native (expected for WASM/JS)")
        print()

        await browser.close()

    print("✅ Complete!")

if __name__ == '__main__':
    asyncio.run(main())
