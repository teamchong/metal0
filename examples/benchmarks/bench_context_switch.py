"""
Context switch benchmark: rapid yield/resume
Tests scheduler overhead
"""
import asyncio
import time

async def ping(n):
    """Yield n times"""
    for _ in range(n):
        await asyncio.sleep(0)  # yield immediately

async def main():
    num_tasks = 10
    yields_per_task = 100000
    total_switches = num_tasks * yields_per_task

    start = time.perf_counter()

    tasks = [ping(yields_per_task) for _ in range(num_tasks)]
    await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    ns_per_switch = (elapsed * 1e9) / total_switches

    print(f"Total context switches: {total_switches:,}")
    print(f"Time: {elapsed:.3f}s")
    print(f"Per-switch: {ns_per_switch:.0f}ns")
    print(f"Throughput: {total_switches/elapsed:,.0f} switches/sec")

if __name__ == "__main__":
    asyncio.run(main())
