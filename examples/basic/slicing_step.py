# Slicing with step parameter
nums = [1, 2, 3, 4, 5, 6, 7, 8]
print(nums[::2])     # [1, 3, 5, 7] - every 2nd element
print(nums[1::2])    # [2, 4, 6, 8] - every 2nd starting at index 1
print(nums[1:7:2])   # [2, 4, 6] - every 2nd from index 1 to 7

text = "hello world"
print(text[::2])     # hlowrd - every 2nd char
print(text[1::2])    # el ol - every 2nd char starting at 1
print(text[0:5:2])   # hlo - every 2nd char in first 5
