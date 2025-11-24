"""Test async comptime inlining - simple version"""

# Simple async function (should be inlined)
async def add(x: int, y: int) -> int:
    return x + y

async def main():
    # This should be compiled as inline call, not spawn
    result = await add(2, 3)
    print(result)

# Manual async execution (no asyncio import needed)
if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
