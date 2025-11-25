"""PyAOT Python Feature Coverage Test - No globals"""

# === ARITHMETIC ===
print("=== Arithmetic ===")
if 2 + 3 == 5:
    print("addition: PASS")
else:
    print("addition: FAIL")

if 5 - 3 == 2:
    print("subtraction: PASS")
else:
    print("subtraction: FAIL")

if 3 * 4 == 12:
    print("multiplication: PASS")
else:
    print("multiplication: FAIL")

if 10 // 3 == 3:
    print("floor_division: PASS")
else:
    print("floor_division: FAIL")

if 10 % 3 == 1:
    print("modulo: PASS")
else:
    print("modulo: FAIL")

if 2 ** 3 == 8:
    print("power: PASS")
else:
    print("power: FAIL")

# === COMPARISON ===
print("=== Comparison ===")
if 5 == 5:
    print("equal: PASS")
if 5 != 3:
    print("not_equal: PASS")
if 3 < 5:
    print("less_than: PASS")
if 5 > 3:
    print("greater_than: PASS")

# === LISTS ===
print("=== Lists ===")
lst = [1, 2, 3]
if len(lst) == 3:
    print("list_len: PASS")
if lst[0] == 1:
    print("list_index: PASS")

# === CONTROL FLOW ===
print("=== Control Flow ===")
result = 0
for i in range(5):
    result = result + i
if result == 10:
    print("for_range: PASS")

# === FUNCTIONS ===
print("=== Functions ===")
def add(a, b):
    return a + b

if add(2, 3) == 5:
    print("function_call: PASS")

def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

if fib(10) == 55:
    print("recursion: PASS")

print("=== Done ===")
