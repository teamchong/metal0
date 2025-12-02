"""
I/O-Bound Benchmark: Concurrent Network Simulation

Tests concurrent I/O handling performance:
- Spawns N worker tasks
- Each worker simulates network latency (sleep)
- Collects results via gather

Best for: event loop / netpoller
"""
import asyncio
import time

NUM_TASKS = 10000
SLEEP_MS = 100  # 100ms simulated I/O latency

async def worker(task_id: int) -> int:
    """I/O-bound worker (simulated network call)"""
    await asyncio.sleep(SLEEP_MS / 1000)
    return task_id

async def main():
    start = time.perf_counter()

    tasks = [worker(i) for i in range(NUM_TASKS)]
    results = await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    total = sum(results)

    print(f"Benchmark: I/O-bound")
    print(f"Tasks: {NUM_TASKS}")
    print(f"Sleep per task: {SLEEP_MS}ms")
    print(f"Total result: {total}")
    print(f"Time: {elapsed*1000:.2f}ms")
    print(f"Tasks/sec: {NUM_TASKS/elapsed:.0f}")
    print(f"Sequential would be: {NUM_TASKS * SLEEP_MS}ms")
    print(f"Concurrency factor: {(NUM_TASKS * SLEEP_MS) / (elapsed * 1000):.0f}x")

if __name__ == "__main__":
    asyncio.run(main())
