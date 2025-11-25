"""
Integration tests for asyncio with goroutine runtime.
These test Python asyncio API compatibility.
"""

import asyncio

# Track test results
passed = 0
failed = 0

def run(name):
    global passed
    passed += 1
    print(f"✓ {name}")

def fail(name, error):
    global failed
    failed += 1
    print(f"✗ {name}: {error}")

# Test 1: Simple async function
async def test_simple_async():
    """Test basic async def and await"""
    async def add(x, y):
        return x + y

    result = await add(2, 3)
    assert result == 5
    run("simple_async")

# Test 2: Multiple awaits
async def test_multiple_awaits():
    """Test multiple await expressions"""
    async def get_value(x):
        return x * 2

    a = await get_value(5)
    b = await get_value(10)
    c = await get_value(15)

    assert a == 10
    assert b == 20
    assert c == 30
    run("multiple_awaits")

# Test 3: asyncio.sleep()
async def test_sleep():
    """Test asyncio.sleep() yields correctly"""
    await asyncio.sleep(0.001)  # 1ms
    run("sleep")

# Test 4: asyncio.gather() - 10 tasks
async def test_gather_small():
    """Test gathering 10 concurrent tasks"""
    async def task(id):
        await asyncio.sleep(0.001)
        return id * 2

    tasks = [task(i) for i in range(10)]
    results = await asyncio.gather(*tasks)

    assert len(results) == 10
    assert results[5] == 10  # 5 * 2
    run("gather_small")

# Test 5: asyncio.gather() - 1000 tasks
async def test_gather_medium():
    """Test gathering 1000 concurrent tasks"""
    async def task(id):
        return id + 1

    tasks = [task(i) for i in range(1000)]
    results = await asyncio.gather(*tasks)

    assert len(results) == 1000
    assert sum(results) == sum(range(1, 1001))
    run("gather_medium")

# Test 6: asyncio.gather() - 100k tasks (stress test)
async def test_gather_large():
    """Test gathering 100k concurrent tasks"""
    async def task(id):
        return 1

    tasks = [task(i) for i in range(100000)]
    results = await asyncio.gather(*tasks)

    assert len(results) == 100000
    run("gather_large")

# Test 7: Nested async calls
async def test_nested_async():
    """Test nested async function calls"""
    async def inner(x):
        return x * 2

    async def middle(x):
        return await inner(x) + 1

    async def outer(x):
        return await middle(x) + 1

    result = await outer(5)
    assert result == 12  # (5*2)+1+1
    run("nested_async")

# Test 8: Error handling
async def test_error_handling():
    """Test that errors propagate correctly"""
    async def failing_task():
        # This should fail
        assert False, "Intentional failure"

    try:
        await failing_task()
        fail("error_handling", "Should have raised AssertionError")
    except AssertionError:
        run("error_handling")

# Main test runner
async def main():
    print("=== AsyncIO Integration Tests ===\n")

    await test_simple_async()
    await test_multiple_awaits()
    await test_sleep()
    await test_gather_small()
    await test_gather_medium()
    await test_gather_large()
    await test_nested_async()
    await test_error_handling()

    print(f"\n=== Results ===")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total: {passed + failed}")

asyncio.run(main())
