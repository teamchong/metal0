"""
Asyncio Fan-out/Fan-in Benchmark (I/O Simulated)

This benchmark simulates I/O-bound tasks:
- Spawns N worker tasks
- Each worker does a small sleep (simulating network latency)
- Collects results via gather

This is where async runtimes shine - handling many concurrent I/O operations.
"""
import asyncio
import time

NUM_TASKS = 10000
SLEEP_MS = 1  # 1ms simulated I/O latency per task

async def worker(task_id: int) -> int:
    """Simulated async worker that waits for I/O"""
    await asyncio.sleep(SLEEP_MS / 1000)  # Convert to seconds
    return task_id

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
    print(f"Sleep per task: {SLEEP_MS}ms")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Tasks/sec: {NUM_TASKS/elapsed:.0f}")
    print(f"Theoretical min (sequential): {NUM_TASKS * SLEEP_MS}ms")

if __name__ == "__main__":
    asyncio.run(main())
