# Test None support - focused tests

# Test 1: Print None directly
print(None)

# Test 2: None comparison (same result should print)
x = None
y = None
if x == y:
    print("Correct: None == None")

# Test 3: None vs int
z = 5
if x == z:
    print("Wrong: None == 5")
else:
    print("Correct: None != 5")
