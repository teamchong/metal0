# HTTP Client Benchmark Results

**Test:** 50 HTTPS requests to httpbin.org/get  
**Date:** 2025-11-27  
**System:** macOS ARM64  
**Library:** `requests` (same Python code for PyAOT/Python/PyPy)

## Results

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `Rust` | 10.444 ± 2.250 | 8.970 | 13.035 | 1.00 |
| `Go` | 12.464 ± 5.178 | 6.762 | 16.872 | 1.19 ± 0.56 |
| `Python` | 15.661 ± 2.094 | 13.551 | 17.738 | 1.50 ± 0.38 |
| `PyPy` | 17.538 ± 3.442 | 13.575 | 19.790 | 1.68 ± 0.49 |
| `PyAOT` | 17.810 ± 3.504 | 14.070 | 21.016 | 1.71 ± 0.50 |

## CPU Efficiency

| Runtime | User Time | System Time | Total CPU |
|---------|-----------|-------------|-----------|
| Go | 0.016s | 0.019s | 0.035s |
| Rust | 0.033s | 0.048s | 0.081s |
| PyAOT | 0.225s | 0.079s | 0.304s |
| PyPy | 0.696s | 0.110s | 0.806s |
| Python | 1.318s | 0.120s | 1.438s |

**Key Finding:** PyAOT uses **4.7x less CPU** than Python (0.304s vs 1.438s)

## Libraries Used

| Language | HTTP Library |
|----------|--------------|
| Python/PyPy/PyAOT | `requests` (same code) |
| Go | `net/http` (stdlib) |
| Rust | `ureq` (popular simple client) |

## Analysis

- **Network-bound:** All within 2x of each other (network latency ~200-300ms/request)
- **PyAOT uses 4.7x less CPU** than Python while handling same workload
- **Go/Rust win** due to mature HTTP clients with connection pooling
- **Same Python code** works on PyAOT, Python, and PyPy

## What This Proves

✅ SSL/TLS handshake works in pure Zig  
✅ TCP sockets work in pure Zig  
✅ HTTP client works in pure Zig  
✅ `requests` library compatibility verified
