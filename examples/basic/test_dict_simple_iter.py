# Minimal test for dict.items() type inference
d = {"a": "val_a"}
for k, v in d.items():
    print(k)
    print(v)
