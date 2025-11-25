import json

class Animal:
    def __init__(self, name, age):
        self.name = name
        self.age = age

    def speak(self):
        return "Generic animal sound"

    def get_info(self):
        return f"{self.name} is {self.age} years old"

class Dog(Animal):
    def __init__(self, name, age, breed):
        super().__init__(name, age)
        self.breed = breed

    def speak(self):
        return "Woof!"

    def fetch(self, item):
        return f"{self.name} fetched {item}"

class Cat(Animal):
    def __init__(self, name, age, color):
        super().__init__(name, age)
        self.color = color

    def speak(self):
        return "Meow!"

    def scratch(self):
        return f"{self.name} is scratching"

class Bird(Animal):
    def __init__(self, name, age, wingspan):
        super().__init__(name, age)
        self.wingspan = wingspan

    def speak(self):
        return "Chirp!"

    def fly(self):
        return f"{self.name} is flying with {self.wingspan}cm wingspan"

class Vehicle:
    def __init__(self, make, model, year):
        self.make = make
        self.model = model
        self.year = year

    def get_description(self):
        return f"{self.year} {self.make} {self.model}"

class Car(Vehicle):
    def __init__(self, make, model, year, doors):
        super().__init__(make, model, year)
        self.doors = doors

    def honk(self):
        return "Beep beep!"

class Truck(Vehicle):
    def __init__(self, make, model, year, capacity):
        super().__init__(make, model, year)
        self.capacity = capacity

    def load(self, weight):
        if weight <= self.capacity:
            return f"Loaded {weight}kg"
        return "Too heavy!"

class Motorcycle(Vehicle):
    def __init__(self, make, model, year, cc):
        super().__init__(make, model, year)
        self.cc = cc

    def rev(self):
        return f"Revving {self.cc}cc engine"

class Database:
    def __init__(self):
        self.data = {}

    def insert(self, key, value):
        self.data[key] = value

    def get(self, key):
        return self.data.get(key)

    def delete(self, key):
        if key in self.data:
            del self.data[key]

class Cache:
    def __init__(self, max_size):
        self.max_size = max_size
        self.cache = {}

    def put(self, key, value):
        if len(self.cache) >= self.max_size:
            first_key = list(self.cache.keys())[0]
            del self.cache[first_key]
        self.cache[key] = value

    def get(self, key):
        return self.cache.get(key)

class Logger:
    def __init__(self, name):
        self.name = name
        self.logs = []

    def info(self, message):
        self.logs.append(f"INFO: {message}")

    def error(self, message):
        self.logs.append(f"ERROR: {message}")

    def get_logs(self):
        return self.logs

def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n-1)

def sum_list(items):
    total = 0
    for item in items:
        total += item
    return total

def product_list(items):
    result = 1
    for item in items:
        result *= item
    return result

def filter_even(items):
    return [x for x in items if x % 2 == 0]

def filter_odd(items):
    return [x for x in items if x % 2 != 0]

def map_double(items):
    return [x * 2 for x in items]

def map_square(items):
    return [x * x for x in items]

def merge_dicts(dict1, dict2):
    result = {}
    for key in dict1:
        result[key] = dict1[key]
    for key in dict2:
        result[key] = dict2[key]
    return result

def reverse_string(s):
    result = ""
    for char in s:
        result = char + result
    return result

def count_vowels(s):
    vowels = "aeiouAEIOU"
    count = 0
    for char in s:
        if char in vowels:
            count += 1
    return count

def is_palindrome(s):
    return s == reverse_string(s)

def find_max(items):
    if not items:
        return None
    max_val = items[0]
    for item in items:
        if item > max_val:
            max_val = item
    return max_val

def find_min(items):
    if not items:
        return None
    min_val = items[0]
    for item in items:
        if item < min_val:
            min_val = item
    return min_val

def bubble_sort(items):
    n = len(items)
    for i in range(n):
        for j in range(0, n-i-1):
            if items[j] > items[j+1]:
                items[j], items[j+1] = items[j+1], items[j]
    return items

def binary_search(items, target):
    left = 0
    right = len(items) - 1
    while left <= right:
        mid = (left + right) // 2
        if items[mid] == target:
            return mid
        elif items[mid] < target:
            left = mid + 1
        else:
            right = mid - 1
    return -1

def linear_search(items, target):
    for i, item in enumerate(items):
        if item == target:
            return i
    return -1

def validate_email(email):
    if "@" not in email:
        return False
    parts = email.split("@")
    if len(parts) != 2:
        return False
    if "." not in parts[1]:
        return False
    return True

def validate_phone(phone):
    digits = 0
    for char in phone:
        if char.isdigit():
            digits += 1
    return digits >= 10

def format_string(template, *args):
    result = template
    for i, arg in enumerate(args):
        placeholder = f"{{{i}}}"
        result = result.replace(placeholder, str(arg))
    return result

def calculate_average(items):
    if not items:
        return 0
    return sum_list(items) / len(items)

def calculate_median(items):
    sorted_items = bubble_sort(items[:])
    n = len(sorted_items)
    if n % 2 == 0:
        return (sorted_items[n//2-1] + sorted_items[n//2]) / 2
    return sorted_items[n//2]

def generate_range(start, end, step):
    result = []
    current = start
    while current < end:
        result.append(current)
        current += step
    return result

def chunk_list(items, chunk_size):
    result = []
    for i in range(0, len(items), chunk_size):
        result.append(items[i:i+chunk_size])
    return result

def flatten_list(nested):
    result = []
    for item in nested:
        if isinstance(item, list):
            for subitem in item:
                result.append(subitem)
        else:
            result.append(item)
    return result

def unique_items(items):
    seen = {}
    result = []
    for item in items:
        if item not in seen:
            seen[item] = True
            result.append(item)
    return result

def intersection(list1, list2):
    result = []
    for item in list1:
        if item in list2 and item not in result:
            result.append(item)
    return result

def union(list1, list2):
    result = list1[:]
    for item in list2:
        if item not in result:
            result.append(item)
    return result

def difference(list1, list2):
    result = []
    for item in list1:
        if item not in list2:
            result.append(item)
    return result

def transpose_matrix(matrix):
    rows = len(matrix)
    cols = len(matrix[0]) if rows > 0 else 0
    result = []
    for j in range(cols):
        row = []
        for i in range(rows):
            row.append(matrix[i][j])
        result.append(row)
    return result

def matrix_multiply(m1, m2):
    rows1 = len(m1)
    cols1 = len(m1[0]) if rows1 > 0 else 0
    rows2 = len(m2)
    cols2 = len(m2[0]) if rows2 > 0 else 0

    if cols1 != rows2:
        return None

    result = []
    for i in range(rows1):
        row = []
        for j in range(cols2):
            sum_val = 0
            for k in range(cols1):
                sum_val += m1[i][k] * m2[k][j]
            row.append(sum_val)
        result.append(row)
    return result

def levenshtein_distance(s1, s2):
    m = len(s1)
    n = len(s2)

    dp = []
    for i in range(m + 1):
        row = []
        for j in range(n + 1):
            row.append(0)
        dp.append(row)

    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if s1[i-1] == s2[j-1]:
                dp[i][j] = dp[i-1][j-1]
            else:
                dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])

    return dp[m][n]

def knapsack(weights, values, capacity):
    n = len(weights)
    dp = []
    for i in range(n + 1):
        row = []
        for j in range(capacity + 1):
            row.append(0)
        dp.append(row)

    for i in range(1, n + 1):
        for w in range(1, capacity + 1):
            if weights[i-1] <= w:
                dp[i][w] = max(values[i-1] + dp[i-1][w-weights[i-1]], dp[i-1][w])
            else:
                dp[i][w] = dp[i-1][w]

    return dp[n][capacity]

def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(n ** 0.5) + 1):
        if n % i == 0:
            return False
    return True

def generate_primes(limit):
    primes = []
    for num in range(2, limit + 1):
        if is_prime(num):
            primes.append(num)
    return primes

def gcd(a, b):
    while b:
        a, b = b, a % b
    return a

def lcm(a, b):
    return (a * b) // gcd(a, b)

def power(base, exp):
    if exp == 0:
        return 1
    if exp < 0:
        return 1.0 / power(base, -exp)
    result = 1
    for _ in range(exp):
        result *= base
    return result

def hamming_weight(n):
    count = 0
    while n:
        count += n & 1
        n >>= 1
    return count

def reverse_bits(n, bits):
    result = 0
    for _ in range(bits):
        result = (result << 1) | (n & 1)
        n >>= 1
    return result

def gray_code(n):
    return n ^ (n >> 1)

def process_animals():
    dog = Dog("Rex", 5, "Labrador")
    cat = Cat("Whiskers", 3, "Orange")
    bird = Bird("Tweety", 1, 15)

    animals = [dog, cat, bird]
    for animal in animals:
        print(animal.speak())
        print(animal.get_info())

def process_vehicles():
    car = Car("Toyota", "Camry", 2020, 4)
    truck = Truck("Ford", "F150", 2019, 1000)
    bike = Motorcycle("Harley", "Sportster", 2021, 883)

    vehicles = [car, truck, bike]
    for vehicle in vehicles:
        print(vehicle.get_description())

def main():
    logger = Logger("AppLogger")
    logger.info("Application started")

    db = Database()
    db.insert("user1", {"name": "Alice", "age": 30})
    db.insert("user2", {"name": "Bob", "age": 25})

    cache = Cache(10)
    cache.put("key1", "value1")
    cache.put("key2", "value2")

    print(fibonacci(10))
    print(factorial(5))
    print(sum_list([1, 2, 3, 4, 5]))
    print(filter_even([1, 2, 3, 4, 5, 6]))
    print(is_palindrome("racecar"))
    print(generate_primes(20))

    process_animals()
    process_vehicles()

    logger.info("Application completed")

if __name__ == "__main__":
    main()
