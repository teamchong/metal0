"""
Async HTTP Demo - Concurrent HTTP requests using PyAOT's async runtime
"""
import asyncio
import http

async def fetch_page(url):
    """Fetch a single page asynchronously"""
    print(f"Fetching {url}...")

    # Simulate async HTTP request
    # In the final implementation, this would be:
    # response = await http.async_get(url)

    await asyncio.sleep(0.1)  # Simulate network delay

    print(f"Got {url}")
    return {"url": url, "status": 200}

async def main():
    """Fetch multiple URLs concurrently"""
    urls = [
        "https://httpbin.org/get",
        "https://httpbin.org/ip",
        "https://httpbin.org/user-agent",
        "https://httpbin.org/headers",
    ]

    # Launch all requests concurrently
    tasks = [fetch_page(url) for url in urls]

    # Wait for all to complete
    results = await asyncio.gather(*tasks)

    print(f"\nFetched {len(results)} pages concurrently")
    for result in results:
        print(f"  - {result['url']}: {result['status']}")

# Run the async main function
asyncio.run(main())
