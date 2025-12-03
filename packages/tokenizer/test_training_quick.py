#!/usr/bin/env python3
"""Quick training comparison test"""
import subprocess
import json

# Run metal0 training
result = subprocess.run(
    ['./zig-out/bin/bench_train'],
    capture_output=True,
    timeout=30
)

output = result.stderr.decode('utf-8')
lines = output.strip().split('\n')

print("=== metal0 BPE Training Output ===")
for line in lines[:20]:  # First 20 lines
    print(line)

if len(lines) > 20:
    print(f"... ({len(lines)-20} more lines)")

# Look for duplicates
merges = []
for line in lines:
    if line.startswith('[') and "'+'" in line:
        merges.append(line.strip())

print(f"\n=== Checking for duplicates ===")
print(f"Total merge lines: {len(merges)}")

from collections import Counter
counts = Counter(merges)
duplicates = [(m, c) for m, c in counts.items() if c > 1]

if duplicates:
    print(f"DUPLICATES FOUND ({len(duplicates)}):")
    for m, c in duplicates[:10]:
        print(f"  {c}x: {m}")
else:
    print("No duplicates found!")
