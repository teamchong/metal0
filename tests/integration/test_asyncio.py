"""Test asyncio support"""
import asyncio

# Test runner
passed = 0
failed = 0

def run(name):
    global passed
    passed += 1
    print(f"{name}: PASS")

# Test 1: Simple asyncio.run
async def hello():
    print("Hello")
    return 42

result = asyncio.run(hello())
assert result == 42
run("asyncio.run simple")

# Test 2: asyncio.sleep
async def test_sleep():
    print("Before sleep")
    await asyncio.sleep(0.01)
    print("After sleep")
    return "done"

result = asyncio.run(test_sleep())
assert result == "done"
run("asyncio.sleep")

# Test 3: Multiple tasks with gather
async def task(id: int):
    await asyncio.sleep(0.01)
    return id * 2

async def test_gather():
    results = await asyncio.gather(
        task(1),
        task(2),
        task(3)
    )
    return results

results = asyncio.run(test_gather())
assert results == [2, 4, 6]
run("asyncio.gather")

# Test 4: create_task
async def worker(n: int):
    await asyncio.sleep(0.01)
    return n * n

async def test_create_task():
    t1 = asyncio.create_task(worker(5))
    t2 = asyncio.create_task(worker(10))

    r1 = await t1
    r2 = await t2

    return r1 + r2

result = asyncio.run(test_create_task())
assert result == 125  # 25 + 100
run("asyncio.create_task")

# Test 5: Many concurrent tasks
async def tiny_task(id: int):
    await asyncio.sleep(0.001)
    return id

async def test_many_tasks():
    tasks = [tiny_task(i) for i in range(100)]
    results = await asyncio.gather(*tasks)
    return sum(results)

result = asyncio.run(test_many_tasks())
assert result == 4950  # sum(0..99)
run("asyncio 100 tasks")

# Test 6: Nested async
async def inner():
    await asyncio.sleep(0.01)
    return "inner"

async def outer():
    result = await inner()
    return f"outer-{result}"

result = asyncio.run(outer())
assert result == "outer-inner"
run("nested async")

print(f"\nPassed: {passed}/{passed + failed}")
