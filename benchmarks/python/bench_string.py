# String benchmark - industry standard workload
# Tests: methods, comparison, length operations
def benchmark():
    n = 100000

    # 1. String method calls (upper/lower) - tests allocation
    s = "Hello World"
    count = 0
    i = 0
    while i < n:
        upper = s.upper()
        lower = s.lower()
        if upper != lower:
            count = count + 1
        i = i + 1

    # 2. String comparison (no allocation)
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

    # 3. Length operations (no allocation)
    total_len = 0
    k = 0
    while k < n:
        total_len = total_len + len(a)
        k = k + 1

    print(count)
    print(matches)
    print(total_len)

benchmark()
