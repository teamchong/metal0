# Test that code builder generates correct code for control flow

# For loop
for i in [1, 2, 3]:
    print(i)

# If statement
x = 10
if x > 5:
    print("large")

# While loop
count = 0
while count < 3:
    count = count + 1
    print(count)

# Function with return
def add(a, b):
    return a + b

result = add(5, 3)
print(result)
