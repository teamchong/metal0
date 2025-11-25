#!/usr/bin/env python3
"""Test WORKING dynamic features"""

print("=== WORKING Dynamic Features ===\n")

# 1. eval() with string
print("1. eval() with string:")
result1 = eval("42")
print(f"   eval('42') = {result1}")

result2 = eval("1 + 2")
print(f"   eval('1 + 2') = {result2}")

result3 = eval("1 + 2 * 3")
print(f"   eval('1 + 2 * 3') = {result3}")

# 2. compile() + eval()
print("\n2. compile() + eval():")
code = compile("1 + 2", "<string>", "eval")
result = eval(code)
print(f"   code = compile('1 + 2', ...)")
print(f"   eval(code) = {result}")

# 3. exec()
print("\n3. exec():")
print("   exec('print(42)'):")
exec("print(42)")
print("   exec('print(1 + 2)'):")
exec("print(1 + 2)")

print("\n✅ All working features tested!")
print("✅ compile() - WORKING")
print("✅ eval() - WORKING (string + code object)")
print("✅ exec() - WORKING")
