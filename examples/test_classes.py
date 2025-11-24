#!/usr/bin/env python3
"""Test class features in PyAOT"""

# Basic class definition
class Person:
    def __init__(self, name: str, age: int):
        self.name = name
        self.age = age

    def greet(self):
        print("Hello, I'm " + self.name)
        print("I'm " + str(self.age) + " years old")

# Test class instantiation
person = Person("Alice", 30)
person.greet()

# Test field access
print("Name: " + person.name)
print("Age: " + str(person.age))

# Test field modification
person.age = 31
print("New age: " + str(person.age))

print("\n✓ Classes working!")
