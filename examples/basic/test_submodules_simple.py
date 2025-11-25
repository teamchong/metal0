# Simple test of submodule support
import testpkg

# Test direct printing (no variables)
print(testpkg.main_func())  # Should print 42
print(testpkg.submod.sub_func())  # Should print 99
