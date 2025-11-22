#!/usr/bin/env python3
import subprocess
import tiktoken

enc = tiktoken.get_encoding("cl100k_base")

text = "Hello world!"
expected = enc.encode(text)

result = subprocess.run(
    ["./zig-out/bin/test_correctness"],
    input=text.encode(),
    capture_output=True
)

if result.returncode != 0:
    print(f"ERROR: {result.stderr.decode()}")
    exit(1)

output = result.stdout.decode().strip()
got = [int(x) for x in output.split()] if output else []

print(f"Text: {text}")
print(f"Expected: {expected}")
print(f"Got:      {got}")
print(f"Match: {expected == got}")
