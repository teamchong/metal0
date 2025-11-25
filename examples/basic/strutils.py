"""String utility module"""

def repeat(text: str, count: int) -> str:
    result = text
    i = 1
    while i < count:
        result = result + text
        i = i + 1
    return result
