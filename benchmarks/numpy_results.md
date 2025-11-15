# NumPy + PyAOT Benchmarks

## Setup

- **Machine:** [To be filled after running]
- **CPU:** [To be filled]
- **RAM:** [To be filled]
- **OS:** macOS (Darwin 25.1.0)
- **Python:** 3.12
- **NumPy:** [To be filled - check with `python -c "import numpy; print(numpy.__version__)")`]
- **PyAOT:** [To be filled - check with `pyaot --version` or git commit]

## Methodology

Each benchmark:
- Runs 2 warmup iterations (excluded from timing)
- Measures wall-clock time for N iterations
- Reports total time for all iterations

## Results

### Scenario A: Pure NumPy Operations

**Hypothesis:** No speedup expected - NumPy already runs in C, PyAOT just calls it via FFI.

| Benchmark | Python+NumPy | PyAOT+NumPy | Speedup | Notes |
|-----------|--------------|-------------|---------|-------|
| Matrix Multiplication (500x500, 5 iter) | X.XXXXs | X.XXXXs | 1.0x | Pure BLAS/LAPACK |
| Universal Functions (1M elements, 10 iter) | X.XXXXs | X.XXXXs | 1.0x | Pure NumPy ufuncs |
| Reductions (10k x 100, 10 iter) | X.XXXXs | X.XXXXs | 1.0x | Aggregations only |

**Expected outcome:** ~1.0x speedup (same performance)

### Scenario B: Mixed NumPy + Python Logic

**Hypothesis:** Moderate speedup - Python loops/conditionals compiled, but NumPy calls dominate.

| Benchmark | Python+NumPy | PyAOT+NumPy | Speedup | Notes |
|-----------|--------------|-------------|---------|-------|
| Conditional Array Ops (10k iter, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | if/else + small arrays |
| Loop Accumulation (5k iter, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | Loops + NumPy ops |
| Nested Loops (100x100, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | O(n²) + arrays |

**Expected outcome:** ~5-15x speedup (Python overhead reduced)

### Scenario C: Mostly Python Logic

**Hypothesis:** Significant speedup - Python logic dominates, NumPy only for final aggregation.

| Benchmark | Python+NumPy | PyAOT+NumPy | Speedup | Notes |
|-----------|--------------|-------------|---------|-------|
| Data Processing (20k iter, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | Heavy conditionals |
| Filtering Pipeline (15k iter, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | Nested conditions |
| Fibonacci + NumPy (10k iter, 5 runs) | X.XXXXs | X.XXXXs | X.Xx | Fibonacci loop |

**Expected outcome:** ~20-40x speedup (same as pure Python benchmarks)

## Summary

| Scenario | Python Logic % | NumPy % | Expected Speedup | Actual Speedup |
|----------|----------------|---------|------------------|----------------|
| A: Pure NumPy | 0% | 100% | 1.0x | X.Xx |
| B: Mixed | 40-60% | 40-60% | 5-15x | X.Xx |
| C: Mostly Python | 80-90% | 10-20% | 20-40x | X.Xx |

## Analysis

### When to Use PyAOT with NumPy

[To be filled after running benchmarks]

**Use PyAOT when:**
- [ ] Heavy Python loops/conditionals around NumPy calls
- [ ] Data processing pipelines with NumPy transformations
- [ ] Business logic with occasional array operations

**Don't use PyAOT when:**
- [ ] Pure NumPy operations (matrix math, vectorized ops)
- [ ] NumPy already dominates execution time
- [ ] No Python logic overhead

### Key Insights

[To be filled after analysis]

1. **Pure NumPy:** PyAOT adds minimal value - NumPy is already optimized C code
2. **Mixed workloads:** Speedup proportional to Python logic percentage
3. **Python-heavy:** Full PyAOT speedup applies (~20-40x)

### Memory Usage

[To be filled if measured]

- Python+NumPy peak memory: X MB
- PyAOT+NumPy peak memory: Y MB

### FFI Overhead

[To be filled if measured]

- Estimated FFI call overhead: X μs per call
- Impact on total runtime: Y%

## Recommendations

[To be filled after analysis]

**For NumPy users:**

1. **Profile first** - Identify if Python or NumPy dominates runtime
2. **Consider PyAOT if:**
   - Loops with conditionals around NumPy calls
   - Data preprocessing/filtering before NumPy
   - Business logic with NumPy transformations
3. **Skip PyAOT if:**
   - Pure vectorized NumPy operations
   - Already using Numba/Cython for hot loops
   - NumPy >90% of execution time

**Future optimizations:**

- [ ] Eliminate FFI overhead by inlining NumPy C API calls
- [ ] JIT compile Python loops around NumPy ops
- [ ] Static analysis to detect pure-NumPy sections

## How to Run These Benchmarks

```bash
# Python baseline
python benchmarks/numpy_comparison.py

# PyAOT version
pyaot benchmarks/numpy_comparison.py

# Or build and run separately
pyaot build benchmarks/numpy_comparison.py /tmp/numpy_bench
/tmp/numpy_bench
```

## Notes

- All benchmarks use deterministic random seeds where possible
- Warmup iterations prevent cold-start bias
- Multiple iterations smooth out OS scheduling noise
- Wall-clock time (not CPU time) for realistic measurements
