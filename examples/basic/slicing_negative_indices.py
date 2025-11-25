# Slicing with negative indices
nums = [1, 2, 3, 4, 5]
print(nums[-2:])     # [4, 5] - last 2 elements
print(nums[:-2])     # [1, 2, 3] - all but last 2
print(nums[-4:-1])   # [2, 3, 4] - middle slice

text = "hello world"
print(text[-5:])     # world - last 5 chars
print(text[:-6])     # hello - all but last 6
print(text[-11:-6])  # hello - first 5 using negatives
