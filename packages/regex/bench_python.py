#!/usr/bin/env python3
"""Python regex benchmark using standard library re module"""
import re
import time

def load_data():
    with open('bench_data.txt', 'r') as f:
        return f.read()

def benchmark_pattern(name, pattern, text, iterations=100000):
    regex = re.compile(pattern)

    # Warmup
    for _ in range(100):
        list(regex.finditer(text))

    # Benchmark
    start = time.perf_counter()
    for _ in range(iterations):
        matches = list(regex.finditer(text))
    end = time.perf_counter()

    elapsed_ms = (end - start) * 1000
    avg_us = (elapsed_ms / iterations) * 1000

    # Count matches
    matches = list(regex.finditer(text))

    return {
        'total_ms': elapsed_ms,
        'avg_us': avg_us,
        'matches': len(matches)
    }

def main():
    text = load_data()

    benchmarks = [
        ('Email', r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
        ('URL', r'https?://[^\s]+'),
        ('Phone', r'\(\d{3}\)\s?\d{3}-\d{4}|\d{3}-\d{3}-\d{4}'),
        ('Digits', r'\d+'),
        ('Word Boundary', r'\b[a-z]{4,}\b'),
        ('Date ISO', r'\d{4}-\d{2}-\d{2}'),
        ('IPv4', r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
        ('Hex Color', r'#[0-9a-fA-F]{6}'),
        ('Version', r'v?\d+\.\d+\.\d+'),
        ('Alphanumeric', r'[a-z]+\d+'),
    ]

    print("=" * 70)
    print("Python Regex Benchmark (re module)")
    print("=" * 70)
    print(f"{'Pattern':<20} {'Matches':<10} {'Avg (µs)':<12} {'Total (ms)':<12}")
    print("-" * 70)

    total_time = 0
    for name, pattern in benchmarks:
        result = benchmark_pattern(name, pattern, text)
        total_time += result['total_ms']
        print(f"{name:<20} {result['matches']:<10} {result['avg_us']:<12.2f} {result['total_ms']:<12.2f}")

    print("-" * 70)
    print(f"{'TOTAL':<20} {'':<10} {'':<12} {total_time:<12.2f}")
    print("=" * 70)

if __name__ == '__main__':
    main()
