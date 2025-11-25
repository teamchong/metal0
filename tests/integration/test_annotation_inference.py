def get_unknown():
    return 42

x: int = get_unknown()  # Should use int, not unknown
y = 42                  # Should infer int
z: str                  # Annotation only

print(x, y)
