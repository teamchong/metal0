"""
CPU-bound benchmark: parallel fibonacci
Tests multi-core parallelism (GIL impact for CPython)
"""
import asyncio
import time

def fib_sync(n):
    """Synchronous fibonacci (CPU intensive)"""
    if n <= 1:
        return n
    return fib_sync(n-1) + fib_sync(n-2)

async def fib(n):
    """Async wrapper for fibonacci"""
    return fib_sync(n)

async def main():
    # 100 parallel fib(30) computations
    # fib(30) = ~832,040 (~100ms on modern CPU)
    num_tasks = 100
    fib_n = 30

    print(f"Computing {num_tasks}x fib({fib_n}) in parallel...")
    start = time.perf_counter()

    tasks = [fib(fib_n) for _ in range(num_tasks)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start

    print(f"Time: {elapsed:.2f}s")
    print(f"Result sample: fib({fib_n}) = {results[0]}")
    print(f"Throughput: {num_tasks/elapsed:.1f} tasks/sec")

    # Estimate core usage (if single-threaded, should be ~10s)
    # If multi-core (8 cores), should be ~1.25s
    single_core_time = 0.1 * num_tasks  # ~10s
    speedup = single_core_time / elapsed
    print(f"Speedup vs single-core: {speedup:.1f}x")

if __name__ == "__main__":
    asyncio.run(main())
