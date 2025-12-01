#!/usr/bin/env python3
"""Test rs-bpe correctness against tiktoken."""

import json
import sys

def main():
    # Load benchmark data
    print("Loading benchmark_data.json...")
    with open("benchmark_data.json", "r") as f:
        data = json.load(f)

    texts = data["texts"][:100]  # First 100 texts
    print(f"Loaded {len(texts)} texts\n")

    # Import tiktoken
    try:
        import tiktoken
    except ImportError:
        print("ERROR: tiktoken not installed")
        print("Run: metal0 install tiktoken")
        sys.exit(1)

    # Import rs-bpe
    try:
        import rs_bpe
    except ImportError:
        print("ERROR: rs-bpe not installed")
        print("Run: metal0 install rs-bpe")
        sys.exit(1)

    # Load encoders
    print("Loading tiktoken encoder (cl100k_base)...")
    tiktoken_enc = tiktoken.get_encoding("cl100k_base")

    print("Loading rs-bpe encoder...")
    rs_bpe_enc = rs_bpe.openai.cl100k_base()

    print(f"Testing {len(texts)} texts...\n")

    # Test each text
    matched = 0
    failed = 0
    first_mismatch = None

    for i, text in enumerate(texts):
        # Get tiktoken tokens
        tiktoken_tokens = tiktoken_enc.encode(text)

        # Get rs-bpe tokens
        rs_bpe_tokens = rs_bpe_enc.encode(text)

        # Compare
        if tiktoken_tokens == rs_bpe_tokens:
            matched += 1
        else:
            failed += 1
            if first_mismatch is None:
                first_mismatch = {
                    "index": i,
                    "text": text[:100] + ("..." if len(text) > 100 else ""),
                    "tiktoken": tiktoken_tokens[:20],  # First 20 tokens
                    "rs_bpe": rs_bpe_tokens[:20],
                    "tiktoken_len": len(tiktoken_tokens),
                    "rs_bpe_len": len(rs_bpe_tokens),
                }

        # Progress
        if (i + 1) % 10 == 0:
            print(f"Progress: {i + 1}/{len(texts)}", end="\r")

    print(" " * 50, end="\r")  # Clear progress line

    # Report results
    total = len(texts)
    accuracy = (matched / total) * 100

    print(f"Tested: {total}/{total} texts")
    print(f"Matched: {matched}/{total}")
    print(f"Failed: {failed}/{total}")
    print(f"Accuracy: {accuracy:.1f}%")
    print()

    if first_mismatch:
        print("First mismatch:")
        print(f"  Index: {first_mismatch['index']}")
        print(f"  Text: {first_mismatch['text']}")
        print(f"  tiktoken length: {first_mismatch['tiktoken_len']}")
        print(f"  rs-bpe length: {first_mismatch['rs_bpe_len']}")
        print(f"  tiktoken tokens (first 20): {first_mismatch['tiktoken']}")
        print(f"  rs-bpe tokens (first 20): {first_mismatch['rs_bpe']}")
        print()

    # Conclusion
    if accuracy == 100.0:
        print("Conclusion: ✅ 100% match - rs-bpe produces identical output to tiktoken")
        sys.exit(0)
    else:
        print(f"Conclusion: ❌ Not 100% match - rs-bpe differs from tiktoken in {failed} cases")
        sys.exit(1)

if __name__ == "__main__":
    main()
