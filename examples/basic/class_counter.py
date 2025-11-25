class Counter:
    def __init__(self, start: int):
        self.value = start

    def increment(self):
        self.value = self.value + 1

    def get(self) -> int:
        return self.value

counter = Counter(0)
counter.increment()
print(counter.get())
