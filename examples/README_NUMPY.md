# NumPy Support in PyAOT

## Current Status

**Import system:** ✅ Implemented
**NumPy FFI:** ⚠️ Partial (Python embedding configuration needed)

## What Works

PyAOT has a complete import system:
- Parser recognizes `import` and `from...import` statements
- Codegen generates Python C API calls
- Runtime has `python.zig` with FFI bindings

## What Needs Work

**Python embedding configuration:**
- Need to set `PYTHONHOME` correctly (requires wchar_t* conversion)
- Need to handle virtual environments
- Need to configure Python paths before `Py_Initialize()`

**Current error:**
```
Fatal Python error: init_fs_encoding: failed to get the Python codec
ModuleNotFoundError: No module named 'encodings'
```

## Approaches for NumPy

### Option 1: Fix Python Embedding (2-3 weeks)
**What to do:**
1. Implement `Py_SetPythonHome()` with proper wchar_t* conversion
2. Detect VIRTUAL_ENV and configure paths
3. Test with system Python and venv Python
4. Handle NumPy imports and array operations

**Benefits:**
- Pure PyAOT + NumPy integration
- Can call any Python library
- Gradual migration path

**Drawbacks:**
- Complex Python C API configuration
- Portability issues (different Python versions)
- Startup overhead (initializing Python interpreter)

### Option 2: Native Array Implementation (6-12 months)
**What to do:**
1. Implement multi-dimensional array type in PyAOT runtime
2. Add numeric types (float32, float64, int32, etc.)
3. Implement core operations (matmul, dot, transpose, broadcast)
4. Add SIMD vectorization
5. Add GPU support (Metal/CUDA)

**Benefits:**
- Zero Python dependency
- Full AOT compilation (instant startup)
- Maximum performance potential

**Drawbacks:**
- Huge engineering effort
- Need to reimplement NumPy from scratch
- Limited compatibility initially

### Option 3: Hybrid Approach (Current Recommendation)
**What to do:**
1. Use PyAOT for general Python code (41x speedup)
2. Keep using Python+NumPy for array operations
3. Add simple FFI for critical paths later

**Benefits:**
- Leverage existing ecosystems
- Focus on PyAOT's strengths (general code)
- Iterative improvement

**Drawbacks:**
- Not "pure" compiled solution
- Two runtimes (PyAOT + Python)

## Benchmarks (Planned)

Once embedding is fixed, benchmark:
- PyAOT calling NumPy vs pure Python+NumPy
- Overhead of FFI calls
- When PyAOT is worth it (more logic, less arrays)

## Next Steps

1. Fix `python.zig` to properly configure PYTHONHOME
2. Create working NumPy demo
3. Benchmark FFI overhead
4. Document when to use PyAOT vs Python+NumPy
