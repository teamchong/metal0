# HTTP Client Benchmark Results

**Test:** 50 HTTPS requests to httpbin.org/get  
**Date:** 2025-11-27  
**System:** macOS ARM64

## Results

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `Go` | 8.936 ± 2.053 | 6.567 | 10.170 | 1.00 |
| `Rust` | 11.544 ± 2.024 | 9.211 | 12.817 | 1.29 ± 0.37 |
| `PyAOT` | 13.838 ± 1.270 | 12.458 | 14.959 | 1.55 ± 0.38 |
| `Python` | 15.115 ± 1.770 | 13.134 | 16.541 | 1.69 ± 0.44 |

## CPU Efficiency

| Runtime | User Time | System Time | Total CPU |
|---------|-----------|-------------|-----------|
| Go | 0.015s | 0.015s | 0.030s |
| Rust | 0.021s | 0.028s | 0.049s |
| PyAOT | 0.126s | 0.039s | 0.165s |
| Python | 0.964s | 0.092s | 1.056s |

**Key Finding:** PyAOT uses **6.4x less CPU** than Python (0.165s vs 1.056s)

## Analysis

- **Network-bound:** All within 2x of each other (network latency ~200-300ms/request)
- **PyAOT vs Python:** 8% faster wall-clock, 84% less CPU usage
- **Go wins:** Mature HTTP client with connection pooling and HTTP/2
- **Rust (ureq):** Simple blocking client, between Go and PyAOT

## Libraries Used

| Language | HTTP Library |
|----------|--------------|
| Python/PyPy/PyAOT | `requests` (same code) |
| Go | `net/http` (stdlib) |
| Rust | `ureq` (popular simple client) |

## What This Proves

- SSL/TLS handshake works in pure Zig
- TCP sockets work in pure Zig  
- HTTP client works in pure Zig
- Same Python code runs on PyAOT, Python, PyPy
