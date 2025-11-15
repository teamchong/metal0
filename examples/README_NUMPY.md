# NumPy Support in PyAOT

## Current Status (2025-01-15)

**Import statement:** ✅ Working (`import numpy`)
**Python embedding:** ✅ Fixed (PYTHONHOME configured)
**Module execution:** ✅ NumPy loads successfully
**Attribute access:** ❌ Not implemented (`np.array` fails)
**Function calls:** ❌ Not implemented (can't call NumPy functions yet)

## What Works

```python
import numpy
print("NumPy imported successfully!")
```

**Output:**
```
Using Python home: /usr/local/...
Adding to sys.path: /path/to/venv/lib/python3.12/site-packages
NumPy imported successfully!
```

**Implementation:**
- ✅ Parser recognizes `import` statements
- ✅ Codegen generates Python C API calls (`python.importModule()`)
- ✅ Runtime configures PYTHONHOME (wchar_t* conversion)
- ✅ Runtime handles virtual environments (VIRTUAL_ENV detection)
- ✅ Python interpreter initializes correctly

## What Doesn't Work Yet

**Module attribute access:**
```python
import numpy as np
arr = np.array([1, 2, 3])  # ❌ Fails: np.array not implemented
```

**Error:**
```
error: ZigCompilationFailed
referenced by: pyaot_main
```

**Root cause:** PyAOT's codegen doesn't support:
1. Accessing attributes from imported modules (`np.array`)
2. Calling Python functions through FFI
3. Converting Zig types to Python objects for FFI calls

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

## Next Steps to Enable NumPy Function Calls

### 1. Implement Module Attribute Access (1-2 weeks)

**Parser changes (src/parser.zig):**
- Already has `.attribute` node type
- Need to handle `module.function` pattern

**Codegen changes (src/codegen/expressions.zig):**
```zig
.attribute => |attr| {
    if (is_imported_module(attr.value)) {
        // Generate: python.getattr(module, "array")
        return try std.fmt.allocPrint(
            allocator,
            "try python.getattr({s}, \"{s}\")",
            .{attr.value.code, attr.attr}
        );
    }
}
```

**Runtime changes (packages/runtime/src/python.zig):**
```zig
pub fn getattr(obj: *anyopaque, name: []const u8) !*anyopaque {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);

    const attr = c.PyObject_GetAttrString(@ptrCast(obj), name_z.ptr);
    if (attr == null) {
        c.PyErr_Print();
        return error.AttributeNotFound;
    }
    return @ptrCast(attr);
}
```

### 2. Implement Python Function Calls (1-2 weeks)

**Codegen changes:**
```zig
.call => |call| {
    if (is_python_function(call.func)) {
        // Convert args: Zig → Python objects
        var py_args = ArrayList(*anyopaque).init(allocator);
        for (call.args) |arg| {
            const py_arg = try convertToPython(arg);
            try py_args.append(py_arg);
        }

        // Generate: python.callFunction(func, args)
        return "try python.callFunction(func, args)";
    }
}
```

**Runtime has:** `callFunction()` already implemented!

### 3. Implement Type Conversion (1 week)

**Already in python.zig:**
- ✅ `fromInt()` - Zig i64 → Python int
- ✅ `fromFloat()` - Zig f64 → Python float
- ✅ `fromString()` - Zig []u8 → Python str
- ✅ `toInt()` - Python int → Zig i64
- ✅ `toFloat()` - Python float → Zig f64

**Need to add:**
- `fromList()` - Zig []PyObject → Python list
- `toList()` - Python list → Zig []PyObject
- Auto-conversion in codegen

### 4. Test and Benchmark

Once implemented:
1. Test `examples/numpy_demo.py`
2. Run `benchmarks/numpy_comparison.py`
3. Document performance characteristics

**Estimated total effort:** 3-5 weeks

---

## Current Achievement

✅ **Python embedding works perfectly!**
✅ **NumPy loads successfully!**
✅ **Foundation for FFI complete!**

**Remaining work:** Module attribute access + function call codegen (3-5 weeks)
