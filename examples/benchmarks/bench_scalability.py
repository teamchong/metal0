import asyncio
import sys
import time

async def task():
    await asyncio.sleep(0)  # Just yield

async def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000

    start = time.time()
    tasks = [task() for _ in range(n)]
    await asyncio.gather(*tasks)
    elapsed = time.time() - start

    throughput = n / elapsed
    print(f"{n:>7} tasks in {elapsed:6.3f}s = {throughput:>10.0f} tasks/sec")

asyncio.run(main())
