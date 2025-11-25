"""
Async Web Crawler - Demonstrates concurrent HTTP requests
"""
import asyncio
import time

async def fetch_url(url, delay=0.1):
    """Fetch a URL with simulated network delay"""
    print(f"[{time.time():.2f}] Fetching: {url}")

    # Simulate async HTTP request
    await asyncio.sleep(delay)

    print(f"[{time.time():.2f}] Done: {url}")
    return {"url": url, "status": 200, "body": f"Content from {url}"}

async def crawl_website(urls):
    """Crawl multiple URLs concurrently"""
    print(f"Starting crawl of {len(urls)} URLs...")
    start = time.time()

    # Spawn all requests at once
    tasks = [fetch_url(url) for url in urls]

    # Wait for all to complete
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start

    print(f"\n=== Crawl Complete ===")
    print(f"Fetched {len(results)} URLs in {elapsed:.2f}s")
    print(f"Sequential would take ~{len(urls) * 0.1:.1f}s")
    print(f"Speedup: {(len(urls) * 0.1) / elapsed:.1f}x")

    return results

# Example usage
urls = [
    "https://example.com/page1",
    "https://example.com/page2",
    "https://example.com/page3",
    "https://example.com/page4",
    "https://example.com/page5",
    "https://example.com/page6",
    "https://example.com/page7",
    "https://example.com/page8",
]

results = asyncio.run(crawl_website(urls))

print(f"\nFetched URLs:")
for result in results:
    print(f"  - {result['url']}: {result['status']}")
