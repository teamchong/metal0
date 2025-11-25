"""Benchmark asyncio scheduler vs Go goroutines"""
import asyncio
import time

async def worker(n: int):
    """Task that yields 100 times"""
    for i in range(100):
        await asyncio.sleep(0)  # Yield to scheduler
    return n

async def main():
    start = time.time()

    # Spawn 100,000 tasks
    tasks = [worker(i) for i in range(100000)]
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start

    print(f"Tasks: 100,000")
    print(f"Time: {elapsed:.3f}s")
    print(f"Tasks/sec: {100000/elapsed:.0f}")

asyncio.run(main())
