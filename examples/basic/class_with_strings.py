class Person:
    def __init__(self, name: str, age: int):
        self.name = name
        self.age = age

    def greet(self):
        print(self.name)
        print(self.age)

p = Person("Alice", 30)
p.greet()
