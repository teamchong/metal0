"""
NumPy with Numba JIT benchmark - Simple program for hyperfine
Uses Numba's @jit decorator for NumPy operations
Runs ~60 seconds on CPython for statistical significance

NOTE: Requires numba: pip install numba
"""
import numpy as np

try:
    from numba import jit
    HAS_NUMBA = True

    @jit(nopython=True)
    def compute(a, b):
        """Compute using NumPy operations (JIT-compiled)"""
        c = a + b
        d = np.sin(c)
        e = np.sqrt(d * d + 1)
        return np.mean(e)

except ImportError:
    # If Numba not available, run without JIT
    HAS_NUMBA = False

    def compute(a, b):
        """Compute using NumPy operations (no JIT)"""
        c = a + b
        d = np.sin(c)
        e = np.sqrt(d * d + 1)
        return np.mean(e)

    print("Warning: Numba not installed - running without JIT")
    print("Install: pip install numba")

# Run ~60 seconds on CPython
result = 0.0
for _ in range(100):
    a = np.arange(1_000_000, dtype=np.float64)
    b = np.arange(1_000_000, dtype=np.float64)
    result = compute(a, b)

print(f"Result: {result}")
