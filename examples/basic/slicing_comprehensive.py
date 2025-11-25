# Comprehensive slicing examples
print("=== List Slicing ===")
nums = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
print(nums[2:7])      # [2, 3, 4, 5, 6]
print(nums[:5])       # [0, 1, 2, 3, 4]
print(nums[5:])       # [5, 6, 7, 8, 9]
print(nums[::3])      # [0, 3, 6, 9]
print(nums[-3:])      # [7, 8, 9]

print("=== String Slicing ===")
text = "Python"
print(text[0:3])      # Pyt
print(text[2:])       # thon
print(text[:4])       # Pyth
print(text[::2])      # Pto
print(text[-3:])      # hon
