class Point:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

    def move(self, dx: int, dy: int):
        self.x = self.x + dx
        self.y = self.y + dy

    def get_x(self) -> int:
        return self.x

    def get_y(self) -> int:
        return self.y


p1 = Point(10, 20)
p2 = Point(5, 15)

print(p1.get_x())  # 10
print(p1.get_y())  # 20

p1.move(3, 7)
print(p1.get_x())  # 13
print(p1.get_y())  # 27

print(p2.get_x())  # 5
print(p2.get_y())  # 15
