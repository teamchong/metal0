"""
Async HTTP benchmark - Simple program for hyperfine
Runs ~60 seconds on CPython for statistical significance
"""
import asyncio

async def fetch_many():
    """Simulate many async HTTP requests"""
    tasks = []
    for i in range(10_000):
        # Simulate async request
        future = asyncio.Future()
        future.set_result({"id": i, "status": 200})
        tasks.append(future)

    results = await asyncio.gather(*tasks)
    return len(results)

# Run 100 times for ~60s on CPython
total = 0
for _ in range(100):
    total += asyncio.run(fetch_many())

print(f"Processed {total} requests")
