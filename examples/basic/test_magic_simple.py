"""
Simple test of magic methods - using primitive types
"""

class Counter:
    def __init__(self):
        self.count = 5

    def __len__(self):
        return self.count

class NumberHolder:
    def __init__(self):
        self.value = 42

    def __getitem__(self, index):
        # Simple: return value + index
        return self.value + index

# Test __len__
c = Counter()
print(len(c))       # Expected: 5

# Test __getitem__
n = NumberHolder()
print(n[0])         # Expected: 42
print(n[1])         # Expected: 43
print(n[10])        # Expected: 52
