"""
NumPy + PyAOT Benchmark Suite

Tests three scenarios to understand when PyAOT provides speedup with NumPy:
- Scenario A: Pure NumPy operations (expect ~1.0x - same speed)
- Scenario B: Mixed NumPy + Python logic (expect moderate speedup)
- Scenario C: Mostly Python logic with some NumPy (expect significant speedup)
"""

import numpy as np
import time


def benchmark(name, func, iterations=10, warmup=2):
    """Run benchmark with warmup iterations"""
    # Warmup
    for _ in range(warmup):
        func()

    # Actual benchmark
    start = time.time()
    for _ in range(iterations):
        result = func()
    elapsed = time.time() - start

    print(f"{name}: {elapsed:.4f}s ({iterations} iterations)")
    return elapsed


# ==============================================================================
# Scenario A: Pure NumPy (expect same speed)
# ==============================================================================

def scenario_a_matmul():
    """Pure matrix multiplication - no Python logic"""
    a = np.random.rand(500, 500)
    b = np.random.rand(500, 500)
    c = a @ b
    return np.sum(c)


def scenario_a_ufuncs():
    """Pure NumPy universal functions"""
    x = np.random.rand(1000000)
    result = np.sin(x) + np.cos(x) * np.exp(-x)
    return np.sum(result)


def scenario_a_reductions():
    """Pure NumPy reductions and aggregations"""
    arr = np.random.rand(10000, 100)
    mean_val = np.mean(arr)
    std_val = np.std(arr)
    max_val = np.max(arr)
    return mean_val + std_val + max_val


# ==============================================================================
# Scenario B: Mixed NumPy + Python logic (expect moderate speedup)
# ==============================================================================

def scenario_b_conditional_ops():
    """Array operations with Python conditionals"""
    result = np.zeros(10000)
    for i in range(10000):
        if i % 2 == 0:
            result[i] = np.sum(np.array([i, i+1, i+2]))
        else:
            result[i] = np.prod(np.array([i, 2]))
    return np.sum(result)


def scenario_b_loop_accumulation():
    """Loop with array operations and accumulation"""
    total = 0
    for i in range(5000):
        arr = np.array([i, i*2, i*3])
        if i % 3 == 0:
            total = total + int(np.sum(arr))
        elif i % 3 == 1:
            total = total + int(np.max(arr))
        else:
            total = total + int(np.min(arr))
    return total


def scenario_b_nested_loops():
    """Nested loops with small array operations"""
    result = 0
    for i in range(100):
        for j in range(100):
            arr = np.array([i, j, i+j])
            if (i + j) % 2 == 0:
                result = result + int(np.sum(arr))
    return result


# ==============================================================================
# Scenario C: Mostly Python logic with some NumPy (expect significant speedup)
# ==============================================================================

def scenario_c_data_processing():
    """Heavy Python logic with occasional NumPy ops"""
    data = []
    for i in range(20000):
        if i % 3 == 0:
            arr = np.array([i, i*2])
            value = int(np.sum(arr))
            data.append(value)
        elif i % 3 == 1:
            arr = np.array([i, i+1, i+2])
            value = int(np.mean(arr))
            data.append(value)
        else:
            data.append(i)

    # Final NumPy aggregation
    result_arr = np.array(data)
    return int(np.sum(result_arr))


def scenario_c_filtering():
    """Python loops with filtering and NumPy transformations"""
    result = []
    for i in range(15000):
        if i % 2 == 0:
            if i % 5 == 0:
                arr = np.array([i, i//5])
                result.append(int(np.max(arr)))
            else:
                result.append(i)

    final = np.array(result)
    return int(np.sum(final))


def scenario_c_fibonacci_with_numpy():
    """Python Fibonacci with NumPy array conversion"""
    a = 0
    b = 1
    total = 0
    for i in range(10000):
        c = a + b
        a = b
        b = c

        # Every 10th number, use NumPy for some operation
        if i % 10 == 0:
            arr = np.array([a, b])
            total = total + int(np.sum(arr))

    return total


# ==============================================================================
# Main benchmark execution
# ==============================================================================

def main():
    print("=" * 70)
    print("NumPy + PyAOT Benchmark Suite")
    print("=" * 70)

    print("\n--- Scenario A: Pure NumPy (expect ~1.0x speedup) ---")
    benchmark("Matrix Multiplication (500x500)", scenario_a_matmul, iterations=5)
    benchmark("Universal Functions (1M elements)", scenario_a_ufuncs, iterations=10)
    benchmark("Reductions (10k x 100)", scenario_a_reductions, iterations=10)

    print("\n--- Scenario B: Mixed NumPy + Python (expect ~5-15x speedup) ---")
    benchmark("Conditional Array Ops", scenario_b_conditional_ops, iterations=5)
    benchmark("Loop Accumulation", scenario_b_loop_accumulation, iterations=5)
    benchmark("Nested Loops", scenario_b_nested_loops, iterations=5)

    print("\n--- Scenario C: Mostly Python (expect ~20-40x speedup) ---")
    benchmark("Data Processing", scenario_c_data_processing, iterations=5)
    benchmark("Filtering Pipeline", scenario_c_filtering, iterations=5)
    benchmark("Fibonacci + NumPy", scenario_c_fibonacci_with_numpy, iterations=5)

    print("\n" + "=" * 70)


if __name__ == "__main__":
    main()
