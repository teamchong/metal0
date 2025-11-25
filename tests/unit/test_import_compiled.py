"""Test importing a compiled module"""

import test_mymodule

result = test_mymodule.add(2, 3)
print(f"test_mymodule.add(2, 3) = {result}")

greeting = test_mymodule.greet("PyAOT")
print(f"test_mymodule.greet('PyAOT') = {greeting}")

print(f"test_mymodule.VERSION = {test_mymodule.VERSION}")

print("✅ Import of compiled module works!")
