import asyncio

async def add(x, y):
    return x + y

async def main():
    result = await add(2, 3)
    print(f"Result: {result}")
    return result

asyncio.run(main())
