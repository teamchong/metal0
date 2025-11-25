"""Test nested import chain: main -> math -> utils"""
import test_math

result = test_math.compute(5)
print("Result:", result)
# Expected: double(5) + triple(5) = 10 + 15 = 25
