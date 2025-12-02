"""
CPU-Bound Benchmark: Real Work (Hash Computation)

Uses hashlib which cannot be computed at compile time.
This measures actual runtime CPU performance.
"""
import asyncio
import time
import hashlib

NUM_TASKS = 1000
HASHES_PER_TASK = 1000

async def worker(task_id: int) -> int:
    """CPU-intensive worker using hash computation"""
    result = 0
    data = f"task_{task_id}".encode()
    for i in range(HASHES_PER_TASK):
        h = hashlib.sha256(data + str(i).encode()).digest()
        result += h[0]  # Use first byte to prevent optimization
    return result

async def main():
    start = time.perf_counter()

    tasks = [worker(i) for i in range(NUM_TASKS)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    total = sum(results)

    print(f"Benchmark: CPU-bound (SHA256)")
    print(f"Tasks: {NUM_TASKS}")
    print(f"Hashes per task: {HASHES_PER_TASK}")
    print(f"Total hashes: {NUM_TASKS * HASHES_PER_TASK}")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Hashes/sec: {(NUM_TASKS * HASHES_PER_TASK)/elapsed:.0f}")

if __name__ == "__main__":
    asyncio.run(main())
