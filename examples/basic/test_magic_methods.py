"""
Test magic methods implementation (__getitem__, __len__)
"""

class MyList:
    def __init__(self):
        self.data = [10, 20, 30]
        self.size = 3

    def __getitem__(self, index):
        return self.data[index]

    def __len__(self):
        return self.size

# Test __getitem__
lst = MyList()
print(lst[0])       # Expected: 10
print(lst[1])       # Expected: 20
print(lst[2])       # Expected: 30

# Test __len__
print(len(lst))     # Expected: 3
