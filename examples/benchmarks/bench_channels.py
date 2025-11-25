"""Channel/Queue benchmark - send/receive 100k messages"""
import asyncio

q = asyncio.Queue(1000)

# Send 100k items
for i in range(100000):
    q.put_nowait(i)

# Receive 100k items
for i in range(100000):
    q.get_nowait()

print("Done")
