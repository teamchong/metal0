# Test fixed-size arrays for constant lists

# Constant lists → arrays (stack allocated)
nums = [1, 2, 3]
names = ["alice", "bob", "charlie"]
flags = [True, False, True]

print(nums[0])    # Should work with array
print(names[1])   # Should work with array
print(flags[2])   # Should work with array

# Dynamic lists → ArrayLists (unchanged)
dynamic = []
dynamic.append(1)
dynamic.append(2)
print(len(dynamic))
