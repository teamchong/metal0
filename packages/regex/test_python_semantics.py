"""
Test Python regex semantics to ensure we match behavior exactly
"""
import re

print("=" * 70)
print("Python Regex Semantics Test")
print("=" * 70)

# Test 1: Greedy quantifiers (default)
print("\n1. Greedy quantifiers:")
text = "aaa"
pattern = "a+"
matches = list(re.finditer(pattern, text))
print(f"  Pattern: {pattern!r}, Text: {text!r}")
print(f"  Matches: {[(m.start(), m.end(), m.group()) for m in matches]}")
print(f"  -> Should match all 'aaa' (greedy)")

# Test 2: Star with overlapping matches
print("\n2. Star behavior:")
text = "aaa"
pattern = "a*"
matches = list(re.finditer(pattern, text))
print(f"  Pattern: {pattern!r}, Text: {text!r}")
print(f"  Matches: {[(m.start(), m.end(), m.group()) for m in matches]}")
print(f"  -> Matches: 'aaa' at 0, '' at 3, '' at 4 (greedy + empty)")

# Test 3: Alternation - leftmost branch wins
print("\n3. Alternation (leftmost):")
text = "cat"
pattern = "cat|c"
matches = list(re.finditer(pattern, text))
print(f"  Pattern: {pattern!r}, Text: {text!r}")
print(f"  Matches: {[(m.start(), m.end(), m.group()) for m in matches]}")
print(f"  -> Should match 'cat' (leftmost branch wins, not longest)")

# Test 4: Character classes exact behavior
print("\n4. Character classes:")
for pattern_name, pattern, text in [
    ("\\d", r"\d", "a1b"),
    ("\\w", r"\w", "a_1-"),
    ("\\s", r"\s", "a b"),
    ("[a-z]", r"[a-z]", "a1B"),
]:
    matches = list(re.finditer(pattern, text))
    print(f"  {pattern_name}: {[(m.start(), m.end(), m.group()) for m in matches]}")

# Test 5: Anchors
print("\n5. Anchors:")
for pattern, text in [
    ("^hello", "hello world"),
    ("^hello", "say hello"),
    ("world$", "hello world"),
    ("world$", "world hello"),
    (r"\bhello\b", "hello world"),
    (r"\bhello\b", "helloworld"),
]:
    matches = list(re.finditer(pattern, text))
    result = "MATCH" if matches else "NO MATCH"
    print(f"  {pattern!r} vs {text!r}: {result}")

# Test 6: Empty matches behavior
print("\n6. Empty matches:")
text = "ab"
pattern = "a*"
matches = list(re.finditer(pattern, text))
print(f"  Pattern: {pattern!r}, Text: {text!r}")
print(f"  Matches: {[(m.start(), m.end(), m.group()) for m in matches]}")
print(f"  -> Python allows empty matches")

# Test 7: Capturing groups
print("\n7. Capturing groups:")
text = "abc123"
pattern = r"([a-z]+)(\d+)"
matches = list(re.finditer(pattern, text))
for m in matches:
    print(f"  Full match: {m.group()}")
    print(f"  Group 1: {m.group(1)}")
    print(f"  Group 2: {m.group(2)}")

print("\n" + "=" * 70)
print("Key Python Regex Semantics:")
print("=" * 70)
print("1. Greedy quantifiers by default (*, +, ?, {n,m})")
print("2. Leftmost match wins (not longest)")
print("3. Empty matches are allowed (a* matches '')")
print("4. Anchors: ^ start, $ end, \\b word boundary")
print("5. Character classes: \\d=[0-9], \\w=[a-zA-Z0-9_], \\s=whitespace")
print("6. Alternation: first branch wins (cat|c matches 'cat' in 'cat')")
print("=" * 70)
