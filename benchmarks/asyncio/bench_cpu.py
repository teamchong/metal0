"""
CPU-Bound Benchmark: Parallel Scaling Test

Measures TRUE parallelism by comparing:
- Sequential: 1 worker does ALL work
- Parallel: N workers split the work

Speedup = Sequential / Parallel (ideal: Nx for N cores)
"""
import asyncio
import time
import hashlib

NUM_WORKERS = 8  # Match CPU cores
WORK_PER_WORKER = 50000  # 50K hash iterations per worker

def do_work(worker_id: int, iterations: int) -> int:
    """CPU-intensive work - SHA256 hashing"""
    h = hashlib.sha256()
    for i in range(iterations):
        h.update(str(worker_id + i).encode())
    return len(h.hexdigest())

async def worker(worker_id: int) -> int:
    """Async wrapper"""
    return do_work(worker_id, WORK_PER_WORKER)

async def main():
    # Sequential: 1 worker does ALL work
    seq_start = time.perf_counter()
    seq_total = do_work(0, NUM_WORKERS * WORK_PER_WORKER)
    seq_time = time.perf_counter() - seq_start

    # Parallel: N workers split work
    par_start = time.perf_counter()
    tasks = [worker(i) for i in range(NUM_WORKERS)]
    results = await asyncio.gather(*tasks)
    par_time = time.perf_counter() - par_start
    par_total = sum(results)

    speedup = seq_time / par_time
    efficiency = (speedup / NUM_WORKERS) * 100

    print(f"Benchmark: Parallel Scaling (SHA256)")
    print(f"Workers: {NUM_WORKERS}")
    print(f"Work/worker: {WORK_PER_WORKER} hashes")
    print(f"Sequential: {seq_time*1000:.2f}ms")
    print(f"Parallel:   {par_time*1000:.2f}ms")
    print(f"Speedup:    {speedup:.2f}x")
    print(f"Efficiency: {efficiency:.0f}%")

if __name__ == "__main__":
    asyncio.run(main())
