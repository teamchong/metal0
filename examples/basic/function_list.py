"""Function with list parameter"""

def sum_list(numbers: list) -> int:
    total = 0
    i = 0
    while i < len(numbers):
        item = numbers[i]
        total = total + item
        i = i + 1
    return total

nums = [1, 2, 3, 4, 5]
result = sum_list(nums)
print(result)
