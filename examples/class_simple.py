class Counter:
    def __init__(self):
        self.count = 0

    def increment(self):
        self.count = self.count + 1

    def get_count(self) -> int:
        return self.count

c = Counter()
c.increment()
c.increment()
print(c.get_count())
