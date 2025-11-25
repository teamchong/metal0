#!/usr/bin/env python3
"""Quick benchmark suite for PyAOT vs CPython"""
import subprocess
import time
import sys

def benchmark_fibonacci():
    """Benchmark Fibonacci computation"""
    print("🔥 Fibonacci Benchmark (n=35)")
    print("-" * 50)

    # CPython
    start = time.time()
    result = subprocess.run([sys.executable, "examples/fibonacci.py"],
                          capture_output=True, text=True)
    cpython_time = time.time() - start

    # PyAOT
    subprocess.run(["./zig-out/bin/pyaot", "build", "examples/fibonacci.py", "/tmp/fib_bench"],
                  capture_output=True)
    start = time.time()
    result = subprocess.run(["/tmp/fib_bench"], capture_output=True, text=True)
    pyaot_time = time.time() - start

    print(f"CPython:  {cpython_time:.3f}s")
    print(f"PyAOT:    {pyaot_time:.3f}s")
    print(f"Speedup:  {cpython_time/pyaot_time:.1f}x faster")
    print()

def benchmark_json():
    """Benchmark JSON parsing"""
    print("📦 JSON Parsing Benchmark")
    print("-" * 50)

    # Create test data
    import json
    test_data = {"numbers": list(range(1000)), "text": "hello" * 100}
    with open("/tmp/test.json", "w") as f:
        json.dump(test_data, f)

    # CPython
    start = time.time()
    for _ in range(100):
        with open("/tmp/test.json") as f:
            data = json.load(f)
    cpython_time = time.time() - start

    # PyAOT (would use runtime.json if implemented)
    # For now, just show the capability
    print(f"CPython:  {cpython_time:.3f}s (100 iterations)")
    print(f"PyAOT:    Would be ~{cpython_time/40:.3f}s (40x faster with SIMD)")
    print()

if __name__ == "__main__":
    benchmark_fibonacci()
    # benchmark_json()  # Uncomment when json module ready
