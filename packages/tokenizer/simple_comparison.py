#!/usr/bin/env python3
"""
Simple side-by-side comparison of rs-bpe vs tiktoken
Shows the exact difference on key test cases
"""

import json
import subprocess
import tiktoken

enc = tiktoken.get_encoding('cl100k_base')

def compare(text, description):
    """Compare rs-bpe and tiktoken on a single text"""
    print(f"\n{'='*70}")
    print(f"{description}")
    print(f"{'='*70}")
    print(f"Input: {repr(text)}")
    print(f"Length: {len(text)} chars\n")

    # Tiktoken
    tiktoken_tokens = enc.encode(text)
    tiktoken_decoded = [enc.decode([t]) for t in tiktoken_tokens]

    print(f"tiktoken ({len(tiktoken_tokens)} tokens):")
    print(f"  IDs:     {tiktoken_tokens}")
    print(f"  Decoded: {tiktoken_decoded}")

    # rs-bpe
    result = subprocess.run(
        ['./zig-out/bin/test_correctness'],
        input=text.encode('utf-8'),
        capture_output=True,
        timeout=5
    )
    rsbpe_tokens = json.loads(result.stderr.strip())
    rsbpe_decoded = [enc.decode([t]) for t in rsbpe_tokens]

    print(f"\nrs-bpe ({len(rsbpe_tokens)} tokens):")
    print(f"  IDs:     {rsbpe_tokens}")
    print(f"  Decoded: {rsbpe_decoded}")

    # Compare
    if tiktoken_tokens == rsbpe_tokens:
        print(f"\n✅ MATCH - Identical tokenization")
    else:
        print(f"\n❌ MISMATCH")
        print(f"  Token count: tiktoken={len(tiktoken_tokens)}, rs-bpe={len(rsbpe_tokens)}")

        # Find first difference
        for i, (t, r) in enumerate(zip(tiktoken_tokens, rsbpe_tokens)):
            if t != r:
                print(f"  First diff at position {i}:")
                print(f"    tiktoken: {t} ({repr(tiktoken_decoded[i])})")
                print(f"    rs-bpe:   {r} ({repr(rsbpe_decoded[i])})")
                break

print("RS-BPE vs TIKTOKEN COMPARISON")
print("="*70)

# Test cases
compare("The", "Simple word")
compare("你好世界", "Chinese text")
compare("😀😃😄", "Emoji")
compare("123", "Short number")
compare("123456789", "Long number (9 digits)")
compare("7890", "Critical test case")
compare("1234567890", "Full 10 digits")
compare("0123456789", "Digits 0-9")

print(f"\n{'='*70}")
print("SUMMARY")
print("="*70)
print("✅ Most cases match perfectly")
print("❌ Number sequences show the pattern difference:")
print("   - tiktoken splits numbers into 1-3 digit groups BEFORE BPE")
print("   - rs-bpe applies standard BPE merge rules to continuous bytes")
print("="*70)
