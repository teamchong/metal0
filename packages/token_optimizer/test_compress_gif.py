import json

# Create a test request with Python code
request = {
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1024,
    "messages": [
        {
            "role": "user",
            "content": """def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

print(fibonacci(10))"""
        }
    ]
}

# Save as JSON
with open('/tmp/test_request.json', 'w') as f:
    json.dump(request, f, indent=2)

print("✅ Created /tmp/test_request.json")
print("Run proxy and send this to test GIF generation")
