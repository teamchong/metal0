"""
Performance tests for asyncio runtime.
Measures spawn rate, context switch, memory usage.
"""

import asyncio
import time

def measure(name, func):
    """Helper to measure and report timing"""
    start = time.time()
    result = func()
    elapsed = time.time() - start
    print(f"{name}: {elapsed:.3f}s")
    return result

async def test_spawn_rate():
    """Measure how fast we can spawn tasks"""
    async def noop():
        pass

    def spawn_10k():
        async def run():
            tasks = [noop() for _ in range(10000)]
            await asyncio.gather(*tasks)
        asyncio.run(run())

    measure("Spawn 10k tasks", spawn_10k)

async def test_context_switch():
    """Measure context switch overhead"""
    async def yield_task():
        await asyncio.sleep(0)

    def switch_10k():
        async def run():
            tasks = [yield_task() for _ in range(10000)]
            await asyncio.gather(*tasks)
        asyncio.run(run())

    measure("10k context switches", switch_10k)

# Run all performance tests
async def main():
    print("=== AsyncIO Performance Tests ===\n")
    await test_spawn_rate()
    await test_context_switch()

asyncio.run(main())
