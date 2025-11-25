import asyncio

async def hello():
    print("Hello from async!")
    return 42

async def main():
    result = await hello()
    print(f"Got: {result}")
    return result

asyncio.run(main())
