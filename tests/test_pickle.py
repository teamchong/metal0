import pickle

# Test pickle.dumps with simple data
data = {"name": "test", "value": 42}
serialized = pickle.dumps(data)
print("Serialized:", serialized)
