import json

class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        return [self.transform(x) for x in self.data]

    def transform(self, x):
        return x * 2

class Calculator:
    def __init__(self):
        self.result = 0

    def add(self, x, y):
        return x + y

    def subtract(self, x, y):
        return x - y

    def multiply(self, x, y):
        return x * y

class TextFormatter:
    def __init__(self, prefix):
        self.prefix = prefix

    def format(self, text):
        return f"{self.prefix}: {text}"

    def uppercase(self, text):
        return text.upper()

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

def filter_even(items):
    return [x for x in items if x % 2 == 0]

def map_double(items):
    return [x * 2 for x in items]

def merge_dicts(dict1, dict2):
    result = {}
    for key in dict1:
        result[key] = dict1[key]
    for key in dict2:
        result[key] = dict2[key]
    return result

def format_string(template, *args):
    result = template
    for i, arg in enumerate(args):
        placeholder = f"{{{i}}}"
        result = result.replace(placeholder, str(arg))
    return result

def validate_email(email):
    if "@" not in email:
        return False
    parts = email.split("@")
    if len(parts) != 2:
        return False
    return True

def process_data():
    processor = DataProcessor([1, 2, 3, 4, 5])
    calc = Calculator()
    formatter = TextFormatter("Result")

    processed = processor.process()
    sum_val = sum_list(processed)
    doubled = map_double(processed)

    return formatter.format(str(sum_val))

def main():
    print(fibonacci(10))
    print(factorial(5))
    print(sum_list([1, 2, 3, 4, 5]))
    print(filter_even([1, 2, 3, 4, 5, 6]))
    print(process_data())

if __name__ == "__main__":
    main()
