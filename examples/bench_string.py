# String benchmark - basic operations
# Tests: comparison, length (no allocation-heavy methods)
def benchmark():
    n = 1000000

    # String comparison (no allocation)
    a = "test_string_alpha_one"
    b = "test_string_alpha_two"
    matches = 0
    j = 0
    while j < n:
        if a == a:
            matches = matches + 1
        if a != b:
            matches = matches + 1
        j = j + 1

    # Length operations (no allocation)
    total_len = 0
    k = 0
    while k < n:
        total_len = total_len + len(a)
        k = k + 1

    print(matches)
    print(total_len)

benchmark()
