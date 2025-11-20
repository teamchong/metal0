#!/usr/bin/env python3
"""
WASM Tokenizer Benchmark - Local HTTP Server
Serves all files locally to avoid CDN issues
"""
import asyncio
from playwright.async_api import async_playwright
import subprocess
import time
import signal
import os

async def main():
    print("🚀 WASM Tokenizer Benchmark (Local Server)")
    print("=" * 60)

    # Start HTTP server
    print("Starting HTTP server on port 8899...")
    server = subprocess.Popen(
        ['python3', '-m', 'http.server', '8899'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(2)

    try:
        async with async_playwright() as p:
            print("Launching Chrome...")
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()

            # Navigate to benchmark page
            await page.goto('http://localhost:8899/bench_wasm.html')

            print("Running benchmarks (10K iterations)...")
            print()

            # Click the run button
            await page.click('button')

            # Wait for results (max 3 minutes)
            try:
                await page.wait_for_selector('table', timeout=180000)
            except:
                print("Timeout waiting for results")
                content = await page.content()
                print(content[:1000])
                return

            # Get the text content
            results_text = await page.inner_text('body')
            print(results_text)

            await browser.close()

    finally:
        print("\nStopping server...")
        server.send_signal(signal.SIGTERM)
        server.wait()

    print("\n✅ Complete!")

if __name__ == '__main__':
    asyncio.run(main())
