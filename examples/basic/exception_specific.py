"""
Specific exception type handling
Demonstrates catching a specific IndexError exception
"""

nums = [1, 2, 3]

try:
    print(nums[10])  # This will raise IndexError
except IndexError:
    print("Index out of bounds")

print("Program continues after exception")
