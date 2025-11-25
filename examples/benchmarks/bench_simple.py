"""
Simple benchmark: 10k noop tasks
Tests task creation/scheduling overhead
"""
import asyncio
import time

async def noop():
    """Empty task - just overhead"""
    pass

async def main():
    start = time.perf_counter()

    tasks = [noop() for _ in range(10000)]
    await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    print(f"Spawned 10k tasks in {elapsed*1000:.2f}ms")
    print(f"Throughput: {10000/elapsed:.0f} tasks/sec")

if __name__ == "__main__":
    asyncio.run(main())
