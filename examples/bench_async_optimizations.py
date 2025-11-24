"""Benchmark async comptime optimizations"""
import asyncio
import time

# Test 1: Simple function (should be inlined by comptime)
async def add(x: int, y: int) -> int:
    return x + y

async def multiply(x: int, y: int) -> int:
    return x * y

# Test 2: Chain of simple awaits (should be parallelized)
async def get_value(x: int) -> int:
    return x

async def test_inlining():
    """Test comptime inlining of simple functions"""
    iterations = 10000
    start = time.time()

    for _ in range(iterations):
        result = await add(2, 3)
        result2 = await multiply(result, 4)

    elapsed = time.time() - start
    ops_per_sec = iterations / elapsed
    print(f"Inlining test: {elapsed:.3f}s ({ops_per_sec:.0f} ops/sec)")

async def test_await_chain():
    """Test await chain optimization"""
    iterations = 1000
    start = time.time()

    for _ in range(iterations):
        # These awaits have no dependencies - could be parallelized
        a = await get_value(1)
        b = await get_value(2)
        c = await get_value(3)
        result = a + b + c

    elapsed = time.time() - start
    ops_per_sec = iterations / elapsed
    print(f"Await chain test: {elapsed:.3f}s ({ops_per_sec:.0f} ops/sec)")

# Run tests
asyncio.run(test_inlining())
asyncio.run(test_await_chain())
print("\nTarget: 5-10x faster than naive spawns")
