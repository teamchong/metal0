"""Function with mixed primitive and runtime types"""

def create_message(count: int, word: str) -> str:
    result = word
    i = 1
    while i < count:
        result = result + " " + word
        i = i + 1
    return result

message = create_message(3, "Hello")
print(message)
