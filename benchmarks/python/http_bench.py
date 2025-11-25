"""
HTTP request creation benchmark - Simple program for hyperfine
Runs ~60 seconds on CPython for statistical significance
"""
import http

# Create 1 million HTTP requests for ~60s on CPython
for _ in range(1_000_000):
    req = http.Request("GET", "https://example.com")
    req.set_header("User-Agent", "PyAOT/1.0")

print("Done")
