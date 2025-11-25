# Test scope resolution
x = 10  # Global

def outer():
    y = 20  # Outer scope

    def inner():
        z = 30  # Inner scope
        print(x)  # Should find global
        print(y)  # Should find outer
        print(z)  # Should find local

    inner()

outer()

# Test method lookup with inheritance
class Animal:
    def speak(self):
        return "sound"

class Dog(Animal):
    def bark(self):
        return "woof"

dog = Dog()
print(dog.speak())  # Inherited method
print(dog.bark())   # Own method
