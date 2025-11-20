#!/usr/bin/env python3
import subprocess, tiktoken, json

TEXT = "The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow."

enc = tiktoken.get_encoding('cl100k_base')
expected = enc.encode(TEXT)

result = subprocess.run(['./zig-out/bin/test_correctness'], capture_output=True, text=True, timeout=10)
got = json.loads(result.stderr.strip())

print(f"Expected: {len(expected)} tokens")
print(f"Got:      {len(got)} tokens")

if got == expected:
    print("\n✅ PASS: PyAOT is 100% CORRECT!")
    exit(0)
else:
    print(f"\n❌ FAIL: Mismatch")
    print(f"Expected: {expected[:20]}")
    print(f"Got:      {got[:20]}")
    exit(1)
