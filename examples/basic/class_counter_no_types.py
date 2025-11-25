class Counter:
    def __init__(self, start):
        self.value = start

    def increment(self):
        self.value = self.value + 1

c = Counter(0)
print(c.value)
c.increment()
print(c.value)
c.increment()
print(c.value)
