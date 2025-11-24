"""
I/O Concurrency benchmark: 10k concurrent "network" operations
Tests work-stealing and multi-core I/O handling

Note: Simplified version without actual HTTP (use asyncio.sleep to simulate I/O)
For real HTTP benchmark, install aiohttp: pip install aiohttp
"""
import asyncio
import time

async def fetch_mock(id):
    """Mock network fetch with sleep (simulates I/O wait)"""
    await asyncio.sleep(0.01)  # 10ms I/O delay
    return f"Response {id}"

async def main():
    num_requests = 10000

    print(f"Starting {num_requests:,} concurrent mock requests...")
    start = time.perf_counter()

    tasks = [fetch_mock(i) for i in range(num_requests)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    req_per_sec = num_requests / elapsed

    print(f"Completed {num_requests:,} requests in {elapsed:.2f}s")
    print(f"Throughput: {req_per_sec:,.0f} req/sec")
    print(f"First result: {results[0]}")

if __name__ == "__main__":
    asyncio.run(main())
