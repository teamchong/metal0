"""Test importing a compiled module"""

import mymodule

result = mymodule.add(2, 3)
print(f"mymodule.add(2, 3) = {result}")

greeting = mymodule.greet("metal0")
print(f"mymodule.greet('metal0') = {greeting}")

print(f"mymodule.VERSION = {mymodule.VERSION}")

print("✅ Import of compiled module works!")
