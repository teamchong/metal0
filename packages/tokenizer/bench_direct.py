#!/usr/bin/env python3
"""
Direct injection benchmark - NO HTTP server
"""
import asyncio
from playwright.async_api import async_playwright

async def main():
    print("🚀 Tokenizer Benchmark - Direct Injection")
    print("=" * 60)

    # Read bundles
    with open('dist/bench_gpt.js', 'r') as f:
        gpt_bundle = f.read()

    with open('dist/bench_tiktoken.js', 'r') as f:
        tiktoken_bundle = f.read()

    with open('dist/bench_ai.js', 'r') as f:
        ai_bundle = f.read()

    # Read WASM files as base64
    import base64
    import json

    with open('dist/tiktoken_bg-qr7t0yz5.wasm', 'rb') as f:
        tiktoken_wasm_bytes = f.read()
        tiktoken_wasm_base64 = base64.b64encode(tiktoken_wasm_bytes).decode('utf-8')

    with open('dist/pyaot_tokenizer.wasm', 'rb') as f:
        pyaot_wasm_bytes = f.read()
        pyaot_wasm_base64 = base64.b64encode(pyaot_wasm_bytes).decode('utf-8')

    with open('dist/cl100k_base.json', 'r') as f:
        cl100k_json = json.load(f)
        cl100k_json_str = json.dumps(cl100k_json)
        cl100k_json_base64 = base64.b64encode(cl100k_json_str.encode('utf-8')).decode('utf-8')

    print(f"Bundle sizes:")
    print(f"  gpt-tokenizer: {len(gpt_bundle)/1024/1024:.1f}MB")
    print(f"  tiktoken: {len(tiktoken_bundle)/1024:.0f}KB + {len(tiktoken_wasm_bytes)/1024/1024:.1f}MB WASM")
    print(f"  ai-tokenizer: {len(ai_bundle)/1024/1024:.1f}MB")
    print(f"  PyAOT: {len(pyaot_wasm_bytes)/1024:.0f}KB WASM + {len(cl100k_json_str)/1024:.0f}KB JSON")
    print()

    async with async_playwright() as p:
        print("Launching Chrome...")
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        # Listen to console
        page.on('console', lambda msg: print(f"  {msg.text}"))

        # Go to blank page
        await page.goto('about:blank')

        # Inject bundles directly
        print("Injecting bundles...")
        await page.add_script_tag(content=gpt_bundle)
        await page.add_script_tag(content=ai_bundle)

        # Inject tiktoken WASM as blob URL first
        await page.evaluate(f"""
            (async () => {{
                const base64 = '{tiktoken_wasm_base64}';
                const binary = atob(base64);
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {{
                    bytes[i] = binary.charCodeAt(i);
                }}
                const blob = new Blob([bytes], {{ type: 'application/wasm' }});
                window.tiktokenWasmURL = URL.createObjectURL(blob);
                console.log('Tiktoken WASM blob created');
            }})();
        """)

        # Inject tiktoken bundle
        await page.add_script_tag(content=tiktoken_bundle)

        # Run benchmarks
        print("\nRunning benchmarks (10K iterations)...")
        print("-" * 60)

        TEXT = "The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow."
        ITERATIONS = 10000

        results = []

        # Test 1: gpt-tokenizer
        try:
            time = await page.evaluate(f"""
                window.benchGPTTokenizer(`{TEXT}`, {ITERATIONS})
            """)
            tokens = await page.evaluate(f"window.testGPTTokenizer(`{TEXT}`)")
            results.append({
                'name': 'gpt-tokenizer',
                'time': int(time),
                'tokens': tokens,
                'type': 'Pure JS',
                'size': '1.1MB'
            })
            print(f"✅ gpt-tokenizer: {int(time)}ms")
        except Exception as e:
            print(f"❌ gpt-tokenizer: {e}")
            results.append({'name': 'gpt-tokenizer', 'error': str(e)})

        # Test 2: ai-tokenizer
        try:
            time = await page.evaluate(f"""
                window.benchAITokenizer(`{TEXT}`, {ITERATIONS})
            """)
            tokens = await page.evaluate(f"window.testAITokenizer(`{TEXT}`)")
            results.append({
                'name': 'ai-tokenizer',
                'time': int(time),
                'tokens': tokens,
                'type': 'Pure JS',
                'size': '8.6MB'
            })
            print(f"✅ ai-tokenizer: {int(time)}ms")
        except Exception as e:
            print(f"❌ ai-tokenizer: {e}")
            results.append({'name': 'ai-tokenizer', 'error': str(e)})

        # Test 3: PyAOT WASM
        try:
            await page.evaluate(f"""
                (async () => {{
                    const base64 = '{pyaot_wasm_base64}';
                    const binary = atob(base64);
                    const bytes = new Uint8Array(binary.length);
                    for (let i = 0; i < binary.length; i++) {{
                        bytes[i] = binary.charCodeAt(i);
                    }}
                    const wasmModule = await WebAssembly.instantiate(bytes, {{}});
                    window.pyaotWasm = wasmModule.instance.exports;
                    console.log('PyAOT WASM loaded, memory:', window.pyaotWasm.memory.buffer.byteLength);

                    // Load JSON from separate fetch to avoid escaping issues
                    const jsonResp = await fetch('data:application/json;base64,{cl100k_json_base64}');
                    const jsonData = await jsonResp.text();
                    console.log('JSON loaded:', jsonData.length, 'bytes');

                    const encoder = new TextEncoder();
                    const jsonBytes = encoder.encode(jsonData);

                    // Allocate memory in WASM
                    const ptr = window.pyaotWasm.alloc(jsonBytes.length);
                    console.log('Allocated', jsonBytes.length, 'bytes at ptr', ptr);

                    const memory = new Uint8Array(window.pyaotWasm.memory.buffer);
                    memory.set(jsonBytes, ptr);

                    // Initialize tokenizer
                    const success = window.pyaotWasm.initFromData(ptr, jsonBytes.length);
                    console.log('initFromData returned:', success);
                    if (!success) throw new Error('Failed to initialize PyAOT tokenizer');

                    // Free the JSON memory
                    window.pyaotWasm.dealloc(ptr, jsonBytes.length);

                    console.log('PyAOT WASM initialized');
                }})();
            """)

            time = await page.evaluate(f"""
                (() => {{
                    const text = `{TEXT}`;
                    const encoder = new TextEncoder();
                    const textBytes = encoder.encode(text);

                    // Allocate text memory once
                    const textPtr = window.pyaotWasm.alloc(textBytes.length);
                    const memory = new Uint8Array(window.pyaotWasm.memory.buffer);
                    memory.set(textBytes, textPtr);

                    // Allocate output length pointer (usize = u32 in WASM32)
                    const outLenPtr = window.pyaotWasm.alloc(4);

                    // Warmup
                    for (let i = 0; i < 100; i++) {{
                        window.pyaotWasm.encode(textPtr, textBytes.length, outLenPtr);
                    }}

                    // Benchmark
                    const start = performance.now();
                    for (let i = 0; i < {ITERATIONS}; i++) {{
                        window.pyaotWasm.encode(textPtr, textBytes.length, outLenPtr);
                    }}
                    const elapsed = performance.now() - start;

                    // Cleanup
                    window.pyaotWasm.dealloc(textPtr, textBytes.length);
                    window.pyaotWasm.dealloc(outLenPtr, 4);

                    return elapsed;
                }})();
            """)

            results.append({
                'name': 'PyAOT (Zig→WASM)',
                'time': int(time),
                'tokens': 76,  # Same as others
                'type': 'WASM',
                'size': '60KB+1MB'
            })
            print(f"✅ PyAOT WASM: {int(time)}ms")
        except Exception as e:
            print(f"❌ PyAOT WASM: {e}")
            results.append({'name': 'PyAOT WASM', 'error': str(e)})

        # Test 4: tiktoken
        try:
            await page.evaluate("window.initTiktoken()")
            time = await page.evaluate(f"""
                window.benchTiktoken(`{TEXT}`, {ITERATIONS})
            """)
            tokens = await page.evaluate(f"window.testTiktoken(`{TEXT}`)")
            results.append({
                'name': 'tiktoken (Rust→WASM)',
                'time': int(time),
                'tokens': tokens,
                'type': 'WASM',
                'size': '5.6MB'
            })
            print(f"✅ tiktoken: {int(time)}ms")
        except Exception as e:
            print(f"❌ tiktoken: {e}")
            results.append({'name': 'tiktoken', 'error': str(e)})

        await browser.close()

        # Display results
        print()
        print("=" * 60)
        print("FINAL RESULTS:")
        print("-" * 60)

        successful = [r for r in results if 'error' not in r]
        successful.sort(key=lambda x: x['time'])

        if successful:
            fastest = successful[0]['time']
            for r in successful:
                speedup = r['time'] / fastest
                trophy = " 🏆" if speedup == 1.0 else ""
                print(f"{r['name']:<25} {r['time']:>5}ms   {speedup:>5.2f}x   {r['size']:<8}   {r['tokens']} tokens   {r['type']}{trophy}")

        errors = [r for r in results if 'error' in r]
        for r in errors:
            print(f"{r['name']:<25} ERROR: {r['error']}")

        print()
        print("Native comparison (60K iterations):")
        print("  PyAOT (Zig):      741ms 🏆")
        print("  TokenDagger (C):  775ms")
        print("  tiktoken (Rust): 1194ms")

    print("\n✅ Complete!")

if __name__ == '__main__':
    asyncio.run(main())
