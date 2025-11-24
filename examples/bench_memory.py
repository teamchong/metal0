"""
Memory benchmark: 1M sleeping tasks
Tests memory overhead per task
"""
import asyncio
import time
import os
import psutil

async def sleep_task(duration):
    """Sleep for specified duration"""
    await asyncio.sleep(duration)

async def main():
    num_tasks = 1_000_000
    sleep_duration = 3600  # 1 hour (won't actually wait this long)

    print(f"Creating {num_tasks:,} sleeping tasks...")

    # Measure initial memory
    process = psutil.Process(os.getpid())
    initial_rss = process.memory_info().rss / (1024 * 1024)  # MB

    start = time.perf_counter()

    # Create all tasks
    tasks = []
    for i in range(num_tasks):
        task = asyncio.create_task(sleep_task(sleep_duration))
        tasks.append(task)

        if i % 100000 == 0 and i > 0:
            print(f"  Created {i:,} tasks...")
            await asyncio.sleep(0)  # yield to let tasks start

    creation_time = time.perf_counter() - start

    # Let tasks actually start
    await asyncio.sleep(1)

    # Measure final memory
    final_rss = process.memory_info().rss / (1024 * 1024)  # MB
    memory_used = final_rss - initial_rss
    bytes_per_task = (memory_used * 1024 * 1024) / num_tasks

    print(f"\nResults:")
    print(f"  Tasks created: {num_tasks:,}")
    print(f"  Creation time: {creation_time:.2f}s")
    print(f"  Memory used: {memory_used:.0f}MB")
    print(f"  Per-task overhead: {bytes_per_task:.0f} bytes")
    print(f"  Creation rate: {num_tasks/creation_time:,.0f} tasks/sec")

    # Cancel all tasks
    for task in tasks:
        task.cancel()

    try:
        await asyncio.gather(*tasks)
    except asyncio.CancelledError:
        pass

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nInterrupted")
