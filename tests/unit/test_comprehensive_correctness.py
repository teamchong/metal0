"""
Comprehensive BPE correctness test - verifies encode/decode round-trip

Usage:
    metal0 test_comprehensive_correctness.py

Tests encode/decode round-trip: decode(encode(text)) == text
"""

from metal0 import tokenizer

# Initialize tokenizer
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")


def run_tests():
    passed = 0
    failed = 0

    print("Running correctness tests...")
    print("")

    # Edge cases
    print("Edge cases...")

    t1 = tokenizer.encode("")
    d1 = tokenizer.decode(t1)
    if d1 == "":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: empty_string")

    t2 = tokenizer.encode(" ")
    d2 = tokenizer.decode(t2)
    if d2 == " ":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: single_space")

    t3 = tokenizer.encode("a")
    d3 = tokenizer.decode(t3)
    if d3 == "a":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: single_char")

    t4 = tokenizer.encode("hello")
    d4 = tokenizer.decode(t4)
    if d4 == "hello":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: short_word")

    t5 = tokenizer.encode("   ")
    d5 = tokenizer.decode(t5)
    if d5 == "   ":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: multiple_spaces")

    t6 = tokenizer.encode("   hello")
    d6 = tokenizer.decode(t6)
    if d6 == "   hello":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: leading_spaces")

    t7 = tokenizer.encode("hello   ")
    d7 = tokenizer.decode(t7)
    if d7 == "hello   ":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: trailing_spaces")

    t8 = tokenizer.encode("hello   world")
    d8 = tokenizer.decode(t8)
    if d8 == "hello   world":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: internal_spaces")

    t10 = tokenizer.encode("0123456789")
    d10 = tokenizer.decode(t10)
    if d10 == "0123456789":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: numbers_only")

    t11 = tokenizer.encode("abc123def456")
    d11 = tokenizer.decode(t11)
    if d11 == "abc123def456":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: mixed_numbers")

    # Real-world cases
    print("Real-world cases...")

    t12 = tokenizer.encode("The quick brown fox jumps over the lazy dog.")
    d12 = tokenizer.decode(t12)
    if d12 == "The quick brown fox jumps over the lazy dog.":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: sentence")

    t14 = tokenizer.encode("def hello(): return 42")
    d14 = tokenizer.decode(t14)
    if d14 == "def hello(): return 42":
        passed = passed + 1
    else:
        failed = failed + 1
        print("FAIL: code")

    # Summary
    print("")
    print("=" * 60)
    total = passed + failed
    if failed == 0:
        print("ALL TESTS PASSED (" + str(passed) + "/" + str(total) + ")")
    else:
        print("FAILED (" + str(passed) + "/" + str(total) + " passed, " + str(failed) + " failed)")
    print("=" * 60)


if __name__ == "__main__":
    run_tests()
