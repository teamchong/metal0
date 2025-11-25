"""
Multiple except blocks
Demonstrates handling different exception types
"""

nums = [1, 2, 3]

# Example 1: IndexError
try:
    print(nums[10])
except IndexError:
    print("Index error caught")
except ValueError:
    print("Value error caught")

# Example 2: Empty list pop
empty = []
try:
    val = empty[0]
    print(val)
except IndexError:
    print("Cannot access empty list")

print("All exceptions handled")
