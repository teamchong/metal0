#!/usr/bin/env python3
"""
Automated benchmark dashboard with JSON export.
"""

import subprocess
import json
import time
import re

def run_cmd(cmd):
    """Run command and return output"""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout + result.stderr

def extract_throughput(output):
    """Extract tasks/sec from benchmark output"""
    match = re.search(r'(\d+[\d,]*)\s+tasks/sec', output.replace(',', ''))
    return int(match.group(1)) if match else 0

def extract_time(output):
    """Extract time from hyperfine output"""
    match = re.search(r'Time.*?:\s+(\d+\.\d+)\s+s', output)
    return float(match.group(1)) if match else 0

def extract_memory_mb(output):
    """Extract memory in MB"""
    match = re.search(r'maximum resident set size:\s+(\d+)', output)
    return int(match.group(1)) / (1024 * 1024) if match else 0

def extract_latency(output):
    """Extract p50, p95, p99 from output"""
    p50 = re.search(r'p50:\s+(\d+\.\d+)', output)
    p95 = re.search(r'p95:\s+(\d+\.\d+)', output)
    p99 = re.search(r'p99:\s+(\d+\.\d+)', output)
    return {
        'p50': float(p50.group(1)) if p50 else 0,
        'p95': float(p95.group(1)) if p95 else 0,
        'p99': float(p99.group(1)) if p99 else 0,
    }

def main():
    print("🚀 Running 5-Dimensional Benchmark...\n")

    results = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'pyaot': {},
        'go': {},
    }

    # 1. Throughput
    print("1️⃣  Throughput...")
    pyaot_out = run_cmd('hyperfine --warmup 1 --runs 3 ./bench_concurrency_final_pyaot')
    go_out = run_cmd('hyperfine --warmup 1 --runs 3 ./bench_concurrency_final_go')
    results['pyaot']['time_s'] = extract_time(pyaot_out)
    results['go']['time_s'] = extract_time(go_out)
    results['pyaot']['throughput'] = 100000 / results['pyaot']['time_s'] if results['pyaot']['time_s'] > 0 else 0
    results['go']['throughput'] = 100000 / results['go']['time_s'] if results['go']['time_s'] > 0 else 0

    # 2. Memory
    print("2️⃣  Memory...")
    pyaot_mem = run_cmd('/usr/bin/time -l ./bench_memory_pyaot 2>&1')
    go_mem = run_cmd('/usr/bin/time -l ./bench_memory_go 2>&1')
    results['pyaot']['memory_mb'] = extract_memory_mb(pyaot_mem)
    results['go']['memory_mb'] = extract_memory_mb(go_mem)

    # 3. Latency
    print("4️⃣  Latency...")
    pyaot_lat = run_cmd('./bench_latency_pyaot')
    go_lat = run_cmd('./bench_latency_go')
    results['pyaot']['latency'] = extract_latency(pyaot_lat)
    results['go']['latency'] = extract_latency(go_lat)

    # Print summary
    print("\n" + "="*60)
    print("RESULTS SUMMARY")
    print("="*60)

    print(f"\n📊 Throughput (100k tasks):")
    print(f"  PyAOT: {results['pyaot']['throughput']:,.0f} tasks/sec")
    print(f"  Go:    {results['go']['throughput']:,.0f} tasks/sec")
    winner = "PyAOT" if results['pyaot']['throughput'] > results['go']['throughput'] else "Go"
    print(f"  Winner: {winner}")

    print(f"\n💾 Memory (100k tasks):")
    print(f"  PyAOT: {results['pyaot']['memory_mb']:.1f} MB")
    print(f"  Go:    {results['go']['memory_mb']:.1f} MB")
    winner = "PyAOT" if results['pyaot']['memory_mb'] < results['go']['memory_mb'] else "Go"
    print(f"  Winner: {winner}")

    print(f"\n⏱️  Latency p99:")
    print(f"  PyAOT: {results['pyaot']['latency']['p99']:.2f}ms")
    print(f"  Go:    {results['go']['latency']['p99']:.2f}ms")
    winner = "PyAOT" if results['pyaot']['latency']['p99'] < results['go']['latency']['p99'] else "Go"
    print(f"  Winner: {winner}")

    # Save results
    with open('benchmark_results.json', 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n✅ Results saved to benchmark_results.json")

if __name__ == '__main__':
    main()
