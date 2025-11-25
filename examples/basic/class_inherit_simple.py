class Animal:
    def __init__(self, name: str):
        self.name = name

    def speak(self) -> str:
        return "Some sound"

class Dog(Animal):
    def __init__(self, name: str, breed: str):
        self.name = name
        self.breed = breed

    def speak(self) -> str:
        return "Woof!"

dog = Dog("Rex", "Labrador")
sound = dog.speak()
print(sound)
print(dog.name)
print(dog.breed)
