"""Simple asyncio.Queue test"""
import asyncio

# Test 1: Create queue and use it
q = asyncio.Queue(10)
q.put_nowait(42)
val = q.get_nowait()
print(f"Got value: {val}")

# Success
print("PASS")
