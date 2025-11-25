import asyncio
import time

latencies = []

async def task():
    start = time.perf_counter()
    await asyncio.sleep(0.001)  # 1ms simulated I/O
    elapsed = (time.perf_counter() - start) * 1000  # Convert to ms
    latencies.append(elapsed)

async def main():
    tasks = [task() for _ in range(10000)]
    await asyncio.gather(*tasks)

    # Sort for percentile calculation
    latencies.sort()
    n = len(latencies)

    p50 = latencies[n // 2]
    p95 = latencies[int(n * 0.95)]
    p99 = latencies[int(n * 0.99)]

    print(f"Latency Distribution (10k tasks):")
    print(f"  p50: {p50:.2f}ms")
    print(f"  p95: {p95:.2f}ms")
    print(f"  p99: {p99:.2f}ms")

asyncio.run(main())
