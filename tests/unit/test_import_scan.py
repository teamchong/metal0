# Test recursive import compilation
import test_mymodule

result = test_mymodule.greet("World")
print(result)

num = test_mymodule.add(5, 3)
print(num)

# Skip VERSION print - module string constants not yet supported
# print("Version:", test_mymodule.VERSION)
