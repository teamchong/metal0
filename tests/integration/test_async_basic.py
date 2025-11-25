# Test basic async/await functionality
passed = 0
failed = 0

def run(name):
    global passed
    passed += 1
    print(f"{name}: PASS")

# Test 1: Simple async function
async def greet(name: str) -> str:
    return f"Hello {name}"

async def test_simple_async():
    """Test simple async function"""
    task = greet("World")
    result = await task
    assert result == "Hello World"
    run("simple_async")

# Test 2: Async with computation
async def compute(x: int) -> int:
    return x * 2 + 10

async def test_async_compute():
    """Test async function with computation"""
    task = compute(15)
    result = await task
    assert result == 40
    run("async_compute")

# Test 3: Multiple async calls
async def add(a: int, b: int) -> int:
    return a + b

async def test_multiple_async():
    """Test multiple async function calls"""
    task1 = add(5, 10)
    task2 = add(20, 30)

    result1 = await task1
    result2 = await task2

    assert result1 == 15
    assert result2 == 50
    run("multiple_async")

# Run tests
async def main():
    await test_simple_async()
    await test_async_compute()
    await test_multiple_async()
    print(f"\nPassed: {passed}/{passed + failed}")

# Execute main
import asyncio
asyncio.run(main())
