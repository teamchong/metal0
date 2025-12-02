"""
CPU-Bound Benchmark: Fan-out/Fan-in

Tests parallel computation performance:
- Spawns N worker tasks
- Each worker does CPU-intensive computation
- Collects results via gather

Best for: thread pool / work-stealing scheduler
"""
import asyncio
import time

NUM_TASKS = 100
WORK_PER_TASK = 20000000  # 20M iterations per task

async def worker(task_id: int) -> int:
    """CPU-intensive worker with I/O to force runtime"""
    await asyncio.sleep(0.001)  # 1ms I/O to force runtime
    result = 0
    for i in range(20000000):  # 20M iterations
        result += i * task_id
    return result

async def main():
    start = time.perf_counter()

    tasks = [worker(i) for i in range(NUM_TASKS)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    total = sum(results)

    print(f"Benchmark: CPU-bound")
    print(f"Tasks: {NUM_TASKS}")
    print(f"Work per task: {WORK_PER_TASK}")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Tasks/sec: {NUM_TASKS/elapsed:.0f}")

if __name__ == "__main__":
    asyncio.run(main())
