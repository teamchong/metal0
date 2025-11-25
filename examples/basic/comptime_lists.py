# Test comptime list evaluation
# List literals with constant elements should be evaluated at compile time

nums = [1, 2, 3, 4, 5]
first = nums[0]
last = nums[-1]
length = len(nums)

print(first)   # Should print: 1
print(last)    # Should print: 5
print(length)  # Should print: 5
