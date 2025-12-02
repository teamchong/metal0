"""
CPU-Bound Benchmark: Fan-out/Fan-in

Tests parallel computation performance:
- Spawns N worker tasks
- Each worker does CPU-intensive hashing (can't be comptime optimized)
- Collects results via gather
"""
import asyncio
import time
import hashlib

NUM_TASKS = 100
WORK_PER_TASK = 10000  # 10K hash iterations per task

async def worker(task_id: int) -> int:
    """CPU-intensive worker using SHA256 hashing"""
    h = hashlib.sha256()
    for i in range(WORK_PER_TASK):
        h.update(str(task_id + i).encode())
    result = h.hexdigest()
    return len(result)

async def main():
    start = time.perf_counter()

    tasks = [worker(i) for i in range(NUM_TASKS)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    total = sum(results)

    print(f"Benchmark: CPU-bound (SHA256)")
    print(f"Tasks: {NUM_TASKS}")
    print(f"Work per task: {WORK_PER_TASK} hashes")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Tasks/sec: {NUM_TASKS/elapsed:.0f}")

if __name__ == "__main__":
    asyncio.run(main())
