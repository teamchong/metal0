# Concurrency benchmark - PyAOT async/await vs Go goroutines
import asyncio
import time

async def worker(task_id: int) -> int:
    """Simulate lightweight async work"""
    await asyncio.sleep(0.001)  # 1ms sleep
    return task_id

async def main():
    num_tasks = 10000  # Start with 10k tasks

    start = time.time()

    # Spawn all tasks
    tasks = []
    for i in range(num_tasks):
        tasks.append(worker(i))

    # Wait for all to complete
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start

    print(f"Completed {num_tasks} tasks in {elapsed:.3f}s")
    print(f"Tasks/sec: {num_tasks / elapsed:.0f}")
    print(f"Avg latency: {elapsed * 1000 / num_tasks:.3f}ms")

asyncio.run(main())
