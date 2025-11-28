import json

f = open("sample.json", "r")
data = f.read()
f.close()

i = 0
while i < 50000:
    parsed = json.loads(data)
    i = i + 1
