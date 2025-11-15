# NumPy Benchmark Design Notes

## What Each Scenario Tests

### Scenario A: Pure NumPy Operations

**Goal:** Establish baseline - prove PyAOT adds no value when NumPy already dominates.

**Test 1: Matrix Multiplication (500x500)**
- Pure BLAS/LAPACK calls
- Zero Python overhead
- Expected: 1.0x speedup (same speed)
- Why: NumPy already runs in C, PyAOT just calls same library

**Test 2: Universal Functions (1M elements)**
- `np.sin()`, `np.cos()`, `np.exp()` - all vectorized C code
- No loops, no conditionals
- Expected: 1.0x speedup
- Why: Entire workload is NumPy C internals

**Test 3: Reductions (10k x 100 array)**
- `np.mean()`, `np.std()`, `np.max()` - aggregation functions
- Pure NumPy operations
- Expected: 1.0x speedup
- Why: No Python logic to optimize

**Key insight:** If your code is 100% NumPy operations, PyAOT won't help.

---

### Scenario B: Mixed NumPy + Python Logic

**Goal:** Show moderate speedup when Python logic wraps NumPy calls.

**Test 1: Conditional Array Ops**
```python
for i in range(10000):
    if i % 2 == 0:
        result[i] = np.sum(np.array([i, i+1, i+2]))
    else:
        result[i] = np.prod(np.array([i, 2]))
```
- 10k iterations of Python if/else
- Each iteration: small NumPy operation
- Expected: 5-10x speedup
- Why: Python loop/conditional compiled away, NumPy calls remain

**Test 2: Loop Accumulation**
```python
total = 0
for i in range(5000):
    arr = np.array([i, i*2, i*3])
    if i % 3 == 0:
        total += np.sum(arr)
    # ...
```
- Python accumulation variable
- Conditional branching
- Small array operations per iteration
- Expected: 8-12x speedup
- Why: Loop overhead + conditional branches optimized

**Test 3: Nested Loops (100x100)**
```python
for i in range(100):
    for j in range(100):
        arr = np.array([i, j, i+j])
        if (i + j) % 2 == 0:
            result += np.sum(arr)
```
- O(n²) Python loop structure
- Conditional inside inner loop
- Expected: 10-15x speedup
- Why: Nested loop overhead significant, PyAOT eliminates it

**Key insight:** When Python logic and NumPy are roughly balanced, PyAOT speedup is proportional to Python logic percentage.

---

### Scenario C: Mostly Python Logic with Some NumPy

**Goal:** Show full PyAOT speedup when Python dominates.

**Test 1: Data Processing**
```python
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
    # ...
```
- Heavy Python loop (20k iterations)
- Conditional branching (3-way if/elif/else)
- List appending (Python operation)
- Small NumPy ops (cheap)
- Final NumPy aggregation at end
- Expected: 25-35x speedup
- Why: ~80% of time in Python logic, only 20% in NumPy

**Test 2: Filtering Pipeline**
```python
result = []
for i in range(15000):
    if i % 2 == 0:
        if i % 5 == 0:
            arr = np.array([i, i//5])
            result.append(np.max(arr))
        else:
            result.append(i)
```
- Nested conditionals (filtering logic)
- Python integer division
- List appending
- Occasional NumPy calls
- Expected: 30-40x speedup
- Why: Dominated by Python branching/filtering logic

**Test 3: Fibonacci + NumPy**
```python
a, b = 0, 1
total = 0
for i in range(10000):
    c = a + b
    a = b
    b = c
    if i % 10 == 0:
        arr = np.array([a, b])
        total += np.sum(arr)
```
- Classic Fibonacci (pure Python loop)
- NumPy only every 10th iteration (~10% of work)
- Expected: 35-42x speedup (close to pure Python Fibonacci)
- Why: 90% of work is Python arithmetic

**Key insight:** When NumPy is just a small part of your workload, PyAOT gives full speedup.

---

## Benchmark Design Principles

### 1. Realistic Data Sizes
- Matrix: 500x500 (250k elements) - realistic ML/data science size
- Vector: 1M elements - common for signal processing
- Iterations: 5-20k - realistic data processing pipelines
- Not toy examples (100 iterations), not unrealistic (1M iterations)

### 2. Multiple Iterations with Warmup
```python
# Warmup (2 iterations) - prevent cold start bias
for _ in range(2):
    func()

# Actual benchmark (5-10 iterations)
start = time.time()
for _ in range(iterations):
    result = func()
elapsed = time.time() - start
```
- Warmup ensures caches are hot, OS scheduling stabilized
- Multiple iterations smooth out noise
- Wall-clock time reflects real-world performance

### 3. Minimal FFI Overhead Tests
- Scenario A: Large NumPy calls (minimal FFI call count)
- Scenario B: Medium-sized arrays (moderate FFI calls)
- Scenario C: Small arrays (frequent FFI calls)

This helps isolate FFI overhead as a factor.

### 4. Cover Common Patterns
- **Data processing:** Filter, transform, aggregate (Scenario C)
- **Scientific computing:** Matrix ops, ufuncs (Scenario A)
- **ML preprocessing:** Loops + conditionals + NumPy (Scenario B)

### 5. Avoid Apples-to-Oranges
- All tests run same algorithm in Python and PyAOT
- Same NumPy version, same library
- Only difference: Python interpreter vs compiled code

---

## Expected Performance Profile

```
Speedup
  40x |                                    *
      |                                  *
      |                               *
  30x |                            *
      |                         *
  20x |                      *
      |                   *
  10x |              *
      |          *
   1x |  *   *
      +--------------------------------
         A1  A2  A3  B1  B2  B3  C1  C2  C3

      Pure NumPy ← → Mixed ← → Python-heavy
```

- **A1-A3:** Flat at 1.0x (NumPy dominates)
- **B1-B3:** Linear increase (Python % increases)
- **C1-C3:** Plateau at max speedup (Python dominates)

---

## How to Interpret Results

### If Scenario A shows >1.1x speedup:
- **Problem:** Measurement error or NumPy version mismatch
- **Action:** Increase iterations, check NumPy installation

### If Scenario B shows <3x speedup:
- **Problem:** NumPy calls dominate more than expected
- **Action:** Profile to confirm Python % is actually 40-60%

### If Scenario C shows <15x speedup:
- **Problem:** NumPy overhead higher than expected OR FFI overhead significant
- **Action:** Check FFI call frequency, consider inlining

### If Scenario C matches pure Python benchmarks (~40x):
- **Success:** Confirms NumPy FFI overhead is negligible
- **Insight:** PyAOT works well even with frequent small NumPy calls

---

## Future Benchmark Extensions

### Memory Profiling
```python
import tracemalloc
tracemalloc.start()
result = scenario_c_data_processing()
peak = tracemalloc.get_traced_memory()[1]
tracemalloc.stop()
```

### FFI Overhead Measurement
```python
# Count NumPy FFI calls
import numpy as np

call_count = 0
original_array = np.array

def tracked_array(*args, **kwargs):
    global call_count
    call_count += 1
    return original_array(*args, **kwargs)

np.array = tracked_array
```

### Profiling Integration
```python
import cProfile
cProfile.run('scenario_b_conditional_ops()')
# Analyze where time is spent: Python logic vs NumPy
```

---

## Recommendations for Users

**Profile your actual code:**
1. Time your script: `time python script.py`
2. Profile it: `python -m cProfile script.py`
3. Identify bottlenecks:
   - If >70% in NumPy → PyAOT won't help much
   - If >70% in Python → PyAOT will give ~30-40x speedup
   - If 50/50 → PyAOT will give ~10-15x speedup

**Use this benchmark as a reference:**
- Match your code pattern to Scenario A/B/C
- Estimate expected speedup
- Measure actual speedup
- If lower than expected → profile to understand why
