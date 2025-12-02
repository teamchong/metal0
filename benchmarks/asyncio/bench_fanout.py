"""
Asyncio Fan-out/Fan-in Benchmark

This benchmark tests the performance of concurrent task execution:
- Spawns N worker tasks
- Each worker does some CPU work (simulated)
- Collects results via gather

Comparison:
- CPython asyncio: Single-threaded event loop
- metal0: Goroutines + work-stealing scheduler + channels
"""
import asyncio
import time

NUM_TASKS = 100
WORK_PER_TASK = 20000000  # 20M iterations per task - CPU bound

async def worker(task_id: int) -> int:
    """Simulated async worker that does some computation"""
    result = 0
    for i in range(WORK_PER_TASK):
        result += i * task_id
    return result

async def main():
    """Fan-out to N workers, fan-in results"""
    start = time.perf_counter()

    # Spawn all tasks
    tasks = [worker(i) for i in range(NUM_TASKS)]

    # Gather results (fan-in)
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    total = sum(results)

    print(f"Tasks: {NUM_TASKS}")
    print(f"Work per task: {WORK_PER_TASK}")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Tasks/sec: {NUM_TASKS/elapsed:.0f}")

if __name__ == "__main__":
    asyncio.run(main())
