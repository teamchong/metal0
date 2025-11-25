"""
Basic try/except example
Demonstrates simple exception handling with a generic except block
"""

nums = [1, 2, 3]

try:
    x = nums[5]  # This will raise IndexError
    print(x)
except:
    print("Error occurred")

print("Program continues")
