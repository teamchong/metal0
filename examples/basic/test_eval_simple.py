# Simple eval() test for PyAOT

# Test 1: Simple constant evaluation
result1 = eval("42")
print("eval('42') =", result1)

# Test 2: Simple arithmetic
result2 = eval("1 + 2")
print("eval('1 + 2') =", result2)

# Test 3: Expression with precedence
result3 = eval("1 + 2 * 3")
print("eval('1 + 2 * 3') =", result3)

print("✅ eval() working!")
