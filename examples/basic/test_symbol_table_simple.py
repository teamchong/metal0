# Test basic scope resolution
x = 10

def foo():
    y = 20
    print(x)
    print(y)

foo()

# Test class method lookup
class Animal:
    def __init__(self):
        self.name = "animal"

    def speak(self):
        print("sound")

class Dog(Animal):
    def bark(self):
        print("woof")

dog = Dog()
dog.speak()  # Inherited method
dog.bark()   # Own method
