import json

f = open("sample.json", "r")
data = f.read()
f.close()

parsed = json.loads(data)
i = 0
while i < 100000:
    s = json.dumps(parsed)
    i = i + 1
