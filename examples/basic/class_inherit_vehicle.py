class Vehicle:
    def __init__(self, wheels: int):
        self.wheels = wheels

    def get_wheels(self) -> int:
        return self.wheels

class Car(Vehicle):
    def __init__(self, wheels: int, doors: int):
        self.wheels = wheels
        self.doors = doors

    def get_doors(self) -> int:
        return self.doors

car = Car(4, 4)
wheels = car.get_wheels()
doors = car.get_doors()
print(wheels)
print(doors)
