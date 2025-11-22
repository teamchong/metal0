#!/usr/bin/env python3
"""
Analyze vocabulary to understand why rs-bpe produces different tokens
"""

import tiktoken

enc = tiktoken.get_encoding('cl100k_base')

# Check specific tokens mentioned in the failures
print("=" * 70)
print("Token Analysis")
print("=" * 70)

# From failure case: "1234567890"
# Expected: [4513, 10961, 16474, 15]
# Got: [4513, 10961, 2495, 1954]

tokens_to_check = {
    4513: None,    # '123'
    10961: None,   # '456'
    16474: None,   # '789'
    15: None,      # Expected for '0'
    2495: None,    # rs-bpe chose for '78'
    1954: None,    # rs-bpe chose for '90'
    11531: None,   # '012'
    12901: None,   # '345'
    17458: None,   # '678'
    19: None,      # Expected for '4' in "1234"
    717: None,     # rs-bpe chose
    1958: None,    # rs-bpe chose
    22: None,      # Expected for '7'
    3080: None,    # rs-bpe chose
    1774: None,    # '45'
}

print("\nDecoding tokens:")
for tok in sorted(tokens_to_check.keys()):
    decoded = enc.decode([tok])
    print(f"  {tok:6d} -> {repr(decoded)}")

# Check if these sequences exist in vocab
print("\n" + "=" * 70)
print("Checking tokenization of problematic sequences")
print("=" * 70)

test_sequences = [
    "0",
    "4",
    "7",
    "789",
    "7890",
    "90",
    "78",
    "012",
]

for seq in test_sequences:
    tokens = enc.encode(seq)
    decoded_tokens = [f"{t}({repr(enc.decode([t]))})" for t in tokens]
    print(f"  '{seq}' -> {tokens} = {', '.join(decoded_tokens)}")

# The key question: why does rs-bpe choose "78" + "90" instead of "789" + "0"?
print("\n" + "=" * 70)
print("BPE Merge Priority Analysis")
print("=" * 70)

# In BPE, longer merges should be preferred, but merge ORDER matters!
# If the vocabulary has these entries, we need to check merge priorities

print("\nFor text '7890':")
print("  Option A (tiktoken): '789' + '0' = [16474, 15]")
print("  Option B (rs-bpe):   '78' + '90' = [2495, 1954]")
print()
print("Both are valid BPE tokenizations, but tiktoken prefers A.")
print("This suggests the merge for '789' happens BEFORE the merge for '90'")
print("in tiktoken's merge rules.")

# Check the actual mergeable ranks
print("\n" + "=" * 70)
print("Checking merge ranks (requires tiktoken internals)")
print("=" * 70)

# Access internal mergeable ranks
try:
    mergeable_ranks = enc._mergeable_ranks

    # Check relevant merges
    merges_to_check = [
        b'789',
        b'78',
        b'90',
        b'012',
        b'0',
        b'4',
        b'7',
    ]

    print("\nMerge ranks (lower rank = applied earlier):")
    for merge in merges_to_check:
        if merge in mergeable_ranks:
            rank = mergeable_ranks[merge]
            print(f"  {merge.decode('utf-8'):10s} -> rank {rank:6d} (token {rank})")
        else:
            print(f"  {merge.decode('utf-8'):10s} -> NOT IN VOCAB")

    # The KEY insight: if '789' has lower rank than '90', it should be applied first
    if b'789' in mergeable_ranks and b'90' in mergeable_ranks:
        rank_789 = mergeable_ranks[b'789']
        rank_90 = mergeable_ranks[b'90']
        print(f"\n  '789' rank: {rank_789}")
        print(f"  '90' rank:  {rank_90}")
        if rank_789 < rank_90:
            print("  => '789' should be merged BEFORE '90' (tiktoken is correct)")
        else:
            print("  => '90' should be merged BEFORE '789' (rs-bpe might be correct?)")

except AttributeError:
    print("Cannot access internal mergeable_ranks")

# Another test: what if we check '01234567890'?
print("\n" + "=" * 70)
print("Extended sequence test")
print("=" * 70)

extended = "01234567890"
tokens = enc.encode(extended)
decoded = [f"{t}({repr(enc.decode([t]))})" for t in tokens]
print(f"tiktoken: '{extended}' ->")
print(f"  {tokens}")
print(f"  {', '.join(decoded)}")
