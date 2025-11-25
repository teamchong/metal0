# Test 1: Simple import (already working)
import json

# Test 2: From import (now should work!)
from json import loads

# Test 3: Use from-imported function
data = loads('{"name": "Alice", "age": 30}')
print(data)

# Test 4: Use module.function syntax
data2 = json.loads('{"city": "NYC"}')
print(data2)

print("All imports work!")
