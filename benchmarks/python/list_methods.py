# List methods benchmark
numbers = []
for i in range(100):
    numbers.append(i)

total = 0
while len(numbers) > 0:
    total = total + numbers.pop()

print(total)
