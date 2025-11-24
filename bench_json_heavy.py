import json

# Heavy workload - 500k json.loads() calls
for i in range(500000):
    obj = json.loads('{"value":42}')
    name = obj["value"]
    print(name)

print("Benchmark complete")
