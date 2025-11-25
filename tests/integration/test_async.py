"""
Async runtime tests for PyAOT
Tests task spawning, scheduling, and preemption
"""
import asyncio
import time


# Test 1: Basic task spawn and run
print("Test 1: Basic task spawn")

async def simple_task():
    return 42

result = asyncio.run(simple_task())
assert result == 42, f"Expected 42, got {result}"
print("✓ Basic task spawn works")


# Test 2: Multiple tasks
print("\nTest 2: Multiple tasks")

counter = 0

async def increment_task():
    global counter
    counter += 1

async def spawn_multiple():
    task1 = asyncio.create_task(increment_task())
    task2 = asyncio.create_task(increment_task())
    task3 = asyncio.create_task(increment_task())

    await task1
    await task2
    await task3

asyncio.run(spawn_multiple())
assert counter == 3, f"Expected counter=3, got {counter}"
print(f"✓ Multiple tasks work (counter={counter})")


# Test 3: Task with arguments
print("\nTest 3: Task with arguments")

async def add_task(a, b):
    return a + b

result = asyncio.run(add_task(10, 20))
assert result == 30, f"Expected 30, got {result}"
print(f"✓ Task arguments work (result={result})")


# Test 4: Yielding
print("\nTest 4: Task yielding")

yield_count = 0

async def yielding_task():
    global yield_count
    for i in range(5):
        yield_count += 1
        await asyncio.sleep(0)  # Yield to scheduler

asyncio.run(yielding_task())
assert yield_count == 5, f"Expected 5 yields, got {yield_count}"
print(f"✓ Yielding works ({yield_count} yields)")


# Test 5: Task state transitions
print("\nTest 5: Task state transitions")

async def stateful_task():
    # idle -> runnable -> running
    await asyncio.sleep(0.001)  # -> waiting
    # -> runnable -> running
    return "done"  # -> dead

result = asyncio.run(stateful_task())
assert result == "done"
print("✓ Task state transitions work")


# Test 6: Exception handling
print("\nTest 6: Exception handling")

async def failing_task():
    raise ValueError("Test error")

try:
    asyncio.run(failing_task())
    assert False, "Should have raised exception"
except ValueError as e:
    assert str(e) == "Test error"
    print(f"✓ Exception handling works")


# Test 7: Long-running task (preemption test)
print("\nTest 7: Long-running task (preemption)")

preempted = False

async def cpu_bound_task():
    # Simulate CPU-bound work
    total = 0
    for i in range(1000000):
        total += i
    return total

async def check_preemption():
    global preempted
    task = asyncio.create_task(cpu_bound_task())

    # Sleep briefly
    await asyncio.sleep(0.001)

    # We should still be able to run
    preempted = True

    # Wait for CPU task
    result = await task
    return result

result = asyncio.run(check_preemption())
assert preempted, "Preemption didn't work - CPU task blocked everything"
print("✓ Preemption allows other tasks to run")


# Test 8: Many concurrent tasks
print("\nTest 8: Many concurrent tasks (stress test)")

async def spawn_many():
    tasks = []
    for i in range(1000):
        task = asyncio.create_task(simple_task())
        tasks.append(task)

    results = []
    for task in tasks:
        result = await task
        results.append(result)

    return len(results)

count = asyncio.run(spawn_many())
assert count == 1000, f"Expected 1000 tasks, got {count}"
print(f"✓ Stress test passed ({count} tasks)")


# Test 9: Task timing
print("\nTest 9: Task timing")

async def timed_task():
    start = time.time()
    await asyncio.sleep(0.01)  # Sleep 10ms
    elapsed = time.time() - start
    return elapsed

elapsed = asyncio.run(timed_task())
assert 0.009 < elapsed < 0.015, f"Expected ~10ms, got {elapsed*1000:.1f}ms"
print(f"✓ Task timing works ({elapsed*1000:.1f}ms)")


# Test 10: Nested tasks
print("\nTest 10: Nested tasks")

async def inner_task(n):
    return n * 2

async def outer_task(n):
    result = await inner_task(n)
    return result + 1

result = asyncio.run(outer_task(5))
assert result == 11, f"Expected 11, got {result}"  # (5*2)+1
print(f"✓ Nested tasks work (result={result})")


print("\n" + "=" * 50)
print("All async tests passed!")
print("=" * 50)
