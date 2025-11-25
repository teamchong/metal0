"""Full Python Feature Coverage - tests what works/broken"""

print("=== ARITHMETIC ===")
print("2+3=" + str(2 + 3))
print("5-3=" + str(5 - 3))
print("3*4=" + str(3 * 4))
print("10//3=" + str(10 // 3))
print("10%3=" + str(10 % 3))
print("2**3=" + str(2 ** 3))

print("=== COMPARISON ===")
if 5 == 5:
    print("== works")
if 5 != 3:
    print("!= works")
if 3 < 5:
    print("< works")
if 5 > 3:
    print("> works")

print("=== STRINGS ===")
s = "hello"
print("len=" + str(len(s)))
print("upper=" + s.upper())
print("concat=" + "a" + "b")

print("=== LISTS ===")
lst = [1, 2, 3]
print("len=" + str(len(lst)))
print("index=" + str(lst[0]))
lst.append(4)
print("after_append=" + str(len(lst)))

print("=== DICT ===")
d = {"a": 1, "b": 2}
print("get=" + str(d["a"]))

print("=== FOR LOOP ===")
total = 0
for i in range(5):
    total = total + i
print("sum_range=" + str(total))

for _ in range(3):
    print("underscore_works")

print("=== WHILE ===")
i = 0
while i < 3:
    print("while_" + str(i))
    i = i + 1

print("=== FUNCTIONS ===")
def add(a, b):
    return a + b
print("add=" + str(add(2, 3)))

def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
print("fib10=" + str(fib(10)))

print("=== DONE ===")
