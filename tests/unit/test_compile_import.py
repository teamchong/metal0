#!/usr/bin/env python3
"""Quick test for compile() and __import__()"""

print("Testing compile():")
code = compile("1 + 2", "<string>", "eval")
result = eval(code)
print(f"compile() + eval() = {result}")

print("\nTesting __import__():")
json = __import__('json')
print(f"__import__('json') = {json}")

print("\n✅ Both work!")
