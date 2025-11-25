# Test if slash in keys causes issues
d = {"/test": "value"}
for k, v in d.items():
    print(k)
    print(v)
