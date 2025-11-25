# Comprehensive test of nested submodule support
import testpkg

# Test main package function
print(testpkg.main_func())

# Test first submodule
print(testpkg.submod.sub_func())

# Test second submodule
print(testpkg.math_utils.add(10, 20))
print(testpkg.math_utils.multiply(5, 7))
