# Test suite for class method edge cases
# Run: metal0 tests/class_methods.py --force

# 1. String methods in class methods (allocator scope test)
class StringProcessor:
    def __init__(self):
        self.prefix = "Hello"

    def process(self):
        x = "world"
        y = x.upper()  # Uses allocator internally
        print(y)

    def process_with_concat(self):
        x = "test"
        y = x.upper()
        z = self.prefix + " " + y
        print(z)


# 2. Reserved word method names (Zig keyword escaping)
class ReservedWords:
    def __init__(self):
        self.value = 42

    def test(self):
        print("test method called")

    def error(self):
        print("error method called")

    def type(self):
        print("type method called")


# 3. Self parameter handling
class SelfHandler:
    def __init__(self, n: int):
        self.n = n

    def get_value(self) -> int:
        return self.n

    def set_value(self, n: int):
        self.n = n

    def double(self):
        self.n = self.n * 2


# 4. Method calling other methods
class MethodChain:
    def __init__(self):
        self.result = 0

    def add(self, x: int):
        self.result = self.result + x

    def multiply(self, x: int):
        self.result = self.result * x

    def compute(self):
        self.add(5)
        self.multiply(3)
        self.add(1)

    def get_result(self) -> int:
        return self.result


# 5. Class with __init__ variants
class InitVariants:
    def __init__(self, a: int, b: int):
        self.a = a
        self.b = b
        self.sum = a + b

    def get_sum(self) -> int:
        return self.sum

    def recalculate(self):
        self.sum = self.a + self.b


# Run all tests
print("=== Test 1: String methods in class ===")
sp = StringProcessor()
sp.process()
sp.process_with_concat()

print("=== Test 2: Reserved word methods ===")
rw = ReservedWords()
rw.test()
rw.error()
rw.type()

print("=== Test 3: Self parameter handling ===")
sh = SelfHandler(10)
print(sh.get_value())
sh.set_value(20)
print(sh.get_value())
sh.double()
print(sh.get_value())

print("=== Test 4: Method calling other methods ===")
mc = MethodChain()
mc.compute()
print(mc.get_result())

print("=== Test 5: Init with multiple params ===")
iv = InitVariants(3, 7)
print(iv.get_sum())
iv.a = 5
iv.recalculate()
print(iv.get_sum())

print("=== All tests passed ===")
