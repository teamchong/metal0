"""
Async Runtime Demo
Demonstrates task spawning, concurrency, and preemptive scheduling
"""
import asyncio
import time


# Example 1: Basic async function
print("Example 1: Basic async function")

async def greet(name):
    print(f"Hello, {name}!")
    return f"Greeted {name}"

result = asyncio.run(greet("PyAOT"))
print(f"Result: {result}\n")


# Example 2: Concurrent tasks
print("Example 2: Concurrent tasks")

async def fetch_data(id):
    print(f"Fetching data {id}...")
    await asyncio.sleep(0.001)  # Simulate I/O
    print(f"Got data {id}")
    return {"id": id, "data": f"result_{id}"}

async def fetch_multiple():
    # Spawn multiple tasks concurrently
    task1 = asyncio.create_task(fetch_data(1))
    task2 = asyncio.create_task(fetch_data(2))
    task3 = asyncio.create_task(fetch_data(3))

    # Wait for all
    result1 = await task1
    result2 = await task2
    result3 = await task3

    return [result1, result2, result3]

results = asyncio.run(fetch_multiple())
print(f"Fetched {len(results)} items\n")


# Example 3: CPU-bound work (preemption)
print("Example 3: CPU-bound work with preemption")

async def cpu_intensive():
    """Simulates heavy computation - should be preempted"""
    print("Starting CPU-intensive task...")
    total = 0
    for i in range(10000000):
        total += i
    print(f"CPU task done: {total}")
    return total

async def quick_task():
    """Quick task that should run despite CPU task"""
    print("Quick task running!")
    await asyncio.sleep(0.001)
    print("Quick task done!")
    return "quick"

async def demonstrate_preemption():
    # Spawn CPU-heavy task
    cpu_task = asyncio.create_task(cpu_intensive())

    # Spawn quick task (should run due to preemption)
    quick = asyncio.create_task(quick_task())

    # Wait for both
    cpu_result = await cpu_task
    quick_result = await quick

    return cpu_result, quick_result

cpu_result, quick_result = asyncio.run(demonstrate_preemption())
print(f"Both tasks completed: cpu={cpu_result}, quick={quick_result}\n")


# Example 4: Task pipeline
print("Example 4: Task pipeline")

async def stage1(data):
    print(f"Stage 1: Processing {data}")
    await asyncio.sleep(0.001)
    return data.upper()

async def stage2(data):
    print(f"Stage 2: Processing {data}")
    await asyncio.sleep(0.001)
    return data + "!!!"

async def stage3(data):
    print(f"Stage 3: Processing {data}")
    await asyncio.sleep(0.001)
    return f"[{data}]"

async def pipeline(input_data):
    result = await stage1(input_data)
    result = await stage2(result)
    result = await stage3(result)
    return result

result = asyncio.run(pipeline("hello"))
print(f"Pipeline result: {result}\n")


# Example 5: Performance test
print("Example 5: Performance test (10,000 tasks)")

async def lightweight_task(n):
    return n * 2

async def spawn_many_tasks():
    start = time.time()

    tasks = []
    for i in range(10000):
        task = asyncio.create_task(lightweight_task(i))
        tasks.append(task)

    results = []
    for task in tasks:
        result = await task
        results.append(result)

    elapsed = time.time() - start
    return len(results), elapsed

count, elapsed = asyncio.run(spawn_many_tasks())
tasks_per_sec = count / elapsed
print(f"Spawned {count} tasks in {elapsed:.3f}s")
print(f"Throughput: {tasks_per_sec:.0f} tasks/sec")
print(f"Target: 1M tasks/sec (current: {tasks_per_sec/1000:.0f}K tasks/sec)\n")


print("=" * 50)
print("Async demo complete!")
print("=" * 50)
print("\nKey features demonstrated:")
print("  ✓ Basic async/await syntax")
print("  ✓ Concurrent task execution")
print("  ✓ Preemptive scheduling (CPU tasks don't block)")
print("  ✓ Task pipelines")
print("  ✓ High throughput (10K+ tasks)")
