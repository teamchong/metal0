"""HTTP client benchmark test."""
import requests

# Benchmark: 10 HTTP requests
i = 0
success = 0
while i < 10:
    resp = requests.get("https://httpbin.org/get")
    if resp.ok:
        success = success + 1
    i = i + 1

print(success)
