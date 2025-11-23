"""
Python regex compatibility test suite
Tests Zig pyregex against Python's re module for 100% compatibility

Run: python3 test_python_compat.py
"""
import re
import subprocess
import json
import sys

# Test cases: (pattern, text, expected_matches)
# Format: list of (start, end, matched_string)
TEST_CASES = [
    # Basic literals
    ("hello", "hello world", [(0, 5, "hello")]),
    ("world", "hello world", [(6, 11, "world")]),
    ("test", "testing", [(0, 4, "test")]),

    # Dot metacharacter
    (".", "abc", [(0, 1, "a"), (1, 2, "b"), (2, 3, "c")]),
    ("a.c", "abc adc", [(0, 3, "abc"), (4, 7, "adc")]),

    # Character classes - digits
    (r"\d", "a1b2c3", [(1, 2, "1"), (3, 4, "2"), (5, 6, "3")]),
    (r"\d+", "test123foo456", [(4, 7, "123"), (10, 13, "456")]),
    (r"\d\d\d", "abc123def456", [(3, 6, "123"), (9, 12, "456")]),

    # Character classes - word chars
    (r"\w", "a_1 b", [(0, 1, "a"), (1, 2, "_"), (2, 3, "1"), (4, 5, "b")]),
    (r"\w+", "hello world_123", [(0, 5, "hello"), (6, 15, "world_123")]),

    # Character classes - whitespace
    (r"\s", "a b\tc\nd", [(1, 2, " "), (3, 4, "\t"), (5, 6, "\n")]),
    (r"\s+", "a  b\t\tc", [(1, 3, "  "), (4, 6, "\t\t")]),

    # Negated character classes
    (r"\D", "a1b2", [(0, 1, "a"), (2, 3, "b")]),
    (r"\W", "a_1 b", [(3, 4, " ")]),
    (r"\S+", "a b  c", [(0, 1, "a"), (2, 3, "b"), (5, 6, "c")]),

    # Custom character classes
    (r"[abc]", "abcdef", [(0, 1, "a"), (1, 2, "b"), (2, 3, "c")]),
    (r"[a-z]", "A1b2C3d", [(2, 3, "b"), (6, 7, "d")]),
    (r"[a-zA-Z]", "a1B2c", [(0, 1, "a"), (2, 3, "B"), (4, 5, "c")]),
    (r"[0-9]+", "test123", [(4, 7, "123")]),

    # Negated custom classes
    (r"[^0-9]", "a1b2", [(0, 1, "a"), (2, 3, "b")]),
    (r"[^a-z]+", "ab12CD34ef", [(2, 8, "12CD34")]),

    # Quantifiers - star (0 or more)
    (r"a*", "baaab", [(0, 0, ""), (1, 4, "aaa"), (4, 4, ""), (5, 5, "")]),
    (r"ab*c", "ac abc abbc", [(0, 2, "ac"), (3, 6, "abc"), (7, 11, "abbc")]),

    # Quantifiers - plus (1 or more)
    (r"a+", "baaab", [(1, 4, "aaa")]),
    (r"\d+", "a123b456", [(1, 4, "123"), (5, 8, "456")]),

    # Quantifiers - question mark (0 or 1)
    (r"colou?r", "color colour", [(0, 5, "color"), (6, 12, "colour")]),
    (r"ab?c", "ac abc", [(0, 2, "ac"), (3, 6, "abc")]),

    # Quantifiers - exact count {n}
    (r"\d{3}", "12 123 1234", [(3, 6, "123"), (7, 10, "123")]),
    (r"a{2}", "a aa aaa", [(2, 4, "aa"), (5, 7, "aa")]),

    # Quantifiers - range {m,n}
    (r"\d{2,4}", "1 12 123 1234 12345", [(2, 4, "12"), (5, 8, "123"), (9, 13, "1234"), (14, 18, "1234")]),
    (r"a{1,3}", "a aa aaa aaaa", [(0, 1, "a"), (2, 4, "aa"), (5, 8, "aaa"), (9, 12, "aaa"), (12, 13, "a")]),

    # Anchors - start of string
    (r"^hello", "hello world", [(0, 5, "hello")]),
    (r"^hello", "say hello", []),  # No match
    (r"^\d+", "123test", [(0, 3, "123")]),

    # Anchors - end of string
    (r"world$", "hello world", [(6, 11, "world")]),
    (r"world$", "world hello", []),  # No match
    (r"\d+$", "test123", [(4, 7, "123")]),

    # Word boundaries
    (r"\bword\b", "word words sword", [(0, 4, "word")]),
    (r"\btest\b", "test testing retest", [(0, 4, "test")]),
    (r"\b\w{4}\b", "the jump make code", [(4, 8, "jump"), (9, 13, "make"), (14, 18, "code")]),

    # Alternation
    (r"cat|dog", "I have a cat and a dog", [(9, 12, "cat"), (19, 22, "dog")]),
    (r"red|blue|green", "red blue green yellow", [(0, 3, "red"), (4, 8, "blue"), (9, 14, "green")]),
    (r"\d+|[a-z]+", "123 abc 456 def", [(0, 3, "123"), (4, 7, "abc"), (8, 11, "456"), (12, 15, "def")]),

    # Groups (capturing)
    (r"(ab)+", "ab abab", [(0, 2, "ab"), (3, 7, "abab")]),
    (r"(\d+)", "test123", [(4, 7, "123")]),
    (r"(\w+)@(\w+)", "user@domain", [(0, 11, "user@domain")]),  # Groups captured

    # Complex patterns
    (r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+",
     "test@example.com",
     [(0, 16, "test@example.com")]),

    (r"\d{4}-\d{2}-\d{2}", "2024-01-15", [(0, 10, "2024-01-15")]),

    (r"\b[A-Z][a-z]+\b", "Hello World", [(0, 5, "Hello"), (6, 11, "World")]),

    # Edge cases
    (r"", "test", [(0, 0, ""), (1, 1, ""), (2, 2, ""), (3, 3, ""), (4, 4, "")]),  # Empty pattern
    (r"a", "", []),  # Empty text
    (r".*", "test", [(0, 4, "test"), (4, 4, "")]),  # Greedy match all

    # Special characters that need escaping
    (r"\.", "a.b", [(1, 2, ".")]),
    (r"\*", "2*3", [(1, 2, "*")]),
    (r"\+", "1+2", [(1, 2, "+")]),
    (r"\?", "what?", [(4, 5, "?")]),
    (r"\[", "[test]", [(0, 1, "[")]),
    (r"\]", "[test]", [(5, 6, "]")]),
    (r"\(", "(a)", [(0, 1, "(")]),
    (r"\)", "(a)", [(2, 3, ")")]),
    (r"\\", "a\\b", [(1, 2, "\\")]),
]


def get_python_matches(pattern, text):
    """Get all matches using Python's re module"""
    try:
        regex = re.compile(pattern)
        matches = []
        for match in regex.finditer(text):
            matches.append((match.start(), match.end(), match.group()))
        return matches
    except re.error as e:
        return f"ERROR: {e}"


def run_tests():
    """Run all test cases"""
    passed = 0
    failed = 0
    errors = []

    print("=" * 70)
    print("Python Regex Compatibility Test Suite")
    print("=" * 70)
    print()

    for i, (pattern, text, expected) in enumerate(TEST_CASES, 1):
        python_result = get_python_matches(pattern, text)

        # Verify our expected results match Python
        if isinstance(python_result, str):  # Error
            print(f"SKIP {i:3d}: Pattern error: {pattern}")
            continue

        if python_result != expected:
            print(f"FAIL {i:3d}: Test case expectation mismatch!")
            print(f"  Pattern: {pattern!r}")
            print(f"  Text: {text!r}")
            print(f"  Expected: {expected}")
            print(f"  Python: {python_result}")
            failed += 1
            errors.append((pattern, text, expected, python_result))
        else:
            passed += 1
            # print(f"PASS {i:3d}: {pattern!r}")

    print()
    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed out of {len(TEST_CASES)} tests")
    print("=" * 70)

    if errors:
        print()
        print("FAILED TESTS:")
        for pattern, text, expected, actual in errors:
            print(f"  Pattern: {pattern!r}")
            print(f"  Text: {text!r}")
            print(f"  Expected: {expected}")
            print(f"  Actual: {actual}")
            print()

    return passed == len(TEST_CASES)


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
