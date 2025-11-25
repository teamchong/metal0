class Shape:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

    def get_x(self) -> int:
        return self.x

    def get_y(self) -> int:
        return self.y

class Rectangle(Shape):
    def __init__(self, x: int, y: int, width: int, height: int):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def area(self) -> int:
        return self.width * self.height

    def get_width(self) -> int:
        return self.width

rect = Rectangle(10, 20, 5, 3)
x = rect.get_x()
y = rect.get_y()
area = rect.area()
width = rect.get_width()
print(x)
print(y)
print(area)
print(width)
