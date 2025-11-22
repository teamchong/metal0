#!/usr/bin/env python3
"""
Verify BPE algorithm: manual step-by-step merge
"""

import tiktoken

enc = tiktoken.get_encoding('cl100k_base')
mergeable_ranks = enc._mergeable_ranks

def manual_bpe(text):
    """
    Manual BPE implementation following the algorithm strictly
    """
    # Start with individual bytes
    tokens = list(text.encode('utf-8'))
    print(f"Input bytes: {tokens}")
    print(f"Input text: {repr(text)}\n")

    iteration = 0
    while True:
        # Find all possible merges and their ranks
        possible_merges = []
        for i in range(len(tokens) - 1):
            # Handle both int and bytes tokens
            left = bytes([tokens[i]]) if isinstance(tokens[i], int) else tokens[i]
            right = bytes([tokens[i+1]]) if isinstance(tokens[i+1], int) else tokens[i+1]
            pair = left + right

            if pair in mergeable_ranks:
                rank = mergeable_ranks[pair]
                possible_merges.append((rank, i, pair))

        if not possible_merges:
            break

        # Find the merge with LOWEST rank (applied earliest in training)
        possible_merges.sort()
        best_rank, best_pos, best_pair = possible_merges[0]

        print(f"Iteration {iteration}:")
        state_repr = []
        for t in tokens:
            if isinstance(t, int):
                state_repr.append(repr(bytes([t]).decode('utf-8', errors='replace')))
            else:
                state_repr.append(repr(t.decode('utf-8', errors='replace')))
        print(f"  State: {state_repr}")
        print(f"  Possible merges: {[(r, p.decode('utf-8', errors='replace')) for r, _, p in possible_merges[:5]]}")
        print(f"  Applying: {repr(best_pair.decode('utf-8', errors='replace'))} (rank {best_rank}) at pos {best_pos}")

        # Apply the merge
        new_tokens = tokens[:best_pos] + [best_pair] + tokens[best_pos+2:]
        tokens = new_tokens

        iteration += 1
        if iteration > 20:
            print("  (stopping after 20 iterations)")
            break

    print(f"\nFinal tokens: {tokens}")
    return tokens

# Test the problematic sequence
print("=" * 70)
print("Manual BPE: '7890'")
print("=" * 70)
result = manual_bpe("7890")
print()

# Now check what tiktoken actually returns
print("=" * 70)
print("Tiktoken result")
print("=" * 70)
tiktoken_result = enc.encode("7890")
print(f"Tokens: {tiktoken_result}")
print(f"Decoded: {[enc.decode([t]) for t in tiktoken_result]}")
print()

# Check if they match
print("=" * 70)
manual_token_ids = [mergeable_ranks[t] if isinstance(t, bytes) else t for t in result]
print(f"Manual token IDs: {manual_token_ids}")
print(f"Tiktoken IDs: {tiktoken_result}")

if manual_token_ids == tiktoken_result:
    print("✅ Manual BPE matches tiktoken")
else:
    print("❌ Manual BPE DIFFERS from tiktoken")
    print(f"   This suggests tiktoken may have special handling or different merge order")
