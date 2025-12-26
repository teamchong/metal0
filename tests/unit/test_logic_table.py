"""Test @logic_table decorator compilation to native code.

This tests that the logic_table module functions compile correctly
and generate proper Zig code with vector operations.
"""

import logic_table

# Test cosine similarity with simple arrays
# Using native array type that compiles to Zig slices
print("Testing logic_table vector operations...")

# Test 1: cosine_sim
a = [1.0, 0.0, 0.0]
b = [1.0, 0.0, 0.0]
result = logic_table.cosine_sim(a, b)
print(f"cosine_sim([1,0,0], [1,0,0]) = {result}")

# Test 2: l2_distance
c = [0.0, 0.0, 0.0]
d = [3.0, 4.0, 0.0]
dist = logic_table.l2_distance(c, d)
print(f"l2_distance([0,0,0], [3,4,0]) = {dist}")

# Test 3: dot_product
e = [1.0, 2.0, 3.0]
f = [4.0, 5.0, 6.0]
dot = logic_table.dot_product(e, f)
print(f"dot_product([1,2,3], [4,5,6]) = {dot}")

print("All logic_table tests completed!")
