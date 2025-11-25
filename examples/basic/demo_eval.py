# Demo: eval(), exec(), and compile() in PyAOT

# Test 1: Simple constant evaluation
result1 = eval("42")
print("eval('42') =", result1)  # Should print 42

# Test 2: Simple arithmetic
result2 = eval("1 + 2")
print("eval('1 + 2') =", result2)  # Should print 3

# Test 3: Expression with precedence
result3 = eval("1 + 2 * 3")
print("eval('1 + 2 * 3') =", result3)  # Should print 7

# Test 4: Float constant
result4 = eval("3.14")
print("eval('3.14') =", result4)  # Should print 3.14

# Test 5: String literal
result5 = eval('"hello"')
print("eval('\"hello\"') =", result5)  # Should print hello

# Test 6: exec() statement
exec("x = 99")
print("exec('x = 99') completed")  # Should print completion message

# Test 7: compile() returns code object
code = compile("1 + 1", "<string>", "eval")
print("compile('1 + 1', '<string>', 'eval') =", code)  # Should print code object

print("\n✅ All eval/exec/compile operations completed!")
print("🚀 PyAOT dynamic code execution working!")
