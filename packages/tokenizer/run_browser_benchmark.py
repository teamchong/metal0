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

    console.log('Testing js-tiktoken...');
    try {
        const { encode } = await import('https://cdn.jsdelivr.net/npm/js-tiktoken@1.0.7/+esm');

        // Warmup
        for (let i = 0; i < 100; i++) encode(TEXT);

        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'js-tiktoken',
            time: Math.round(elapsed),
            tokens: encode(TEXT).length
        });
    } catch (e) {
        results.push({ name: 'js-tiktoken', error: e.message });
    }

    console.log('Testing gpt-tokenizer...');
    try {
        const { encode } = await import('https://cdn.jsdelivr.net/npm/gpt-tokenizer@2.1.1/+esm');

        for (let i = 0; i < 100; i++) encode(TEXT);

        const start = performance.now();
        for (let i = 0; i < ITERATIONS; i++) encode(TEXT);
        const elapsed = performance.now() - start;

        results.push({
            name: 'gpt-tokenizer',
            time: Math.round(elapsed),
            tokens: encode(TEXT).length
        });
    } catch (e) {
        results.push({ name: 'gpt-tokenizer', error: e.message });
    }

    return results;
})()
"""

async def main():
    print("🚀 Browser Tokenizer Benchmark")
    print("=" * 60)

    async with async_playwright() as p:
        print("Launching Chrome...")
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        # Go to blank page
        await page.goto('about:blank')

        print("Running benchmarks (10K iterations)...")
        print()

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
                print(f"{r['name']:<20} {r['time']:>6}ms   {speedup:>5.2f}x   {r['tokens']} tokens{trophy}")

        # Show errors
        errors = [r for r in results if 'error' in r]
        for r in errors:
            print(f"{r['name']:<20} ERROR: {r['error']}")

        print()
        print("=" * 60)
        print("Comparison with native:")
        print("  PyAOT (Zig native):  820ms  (60K iterations)")
        print("  Browser (WASM/JS):   ~3-6x slower (expected)")
        print()

        await browser.close()

    print("✅ Complete!")

if __name__ == '__main__':
    asyncio.run(main())
