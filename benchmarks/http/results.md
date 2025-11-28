# HTTP Client Benchmark Results

**Test:** 50 HTTPS requests to httpbin.org/get
**Date:** 2025-11-27
**System:** macOS ARM64

## Results

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `PyAOT` | 13.998 ± 0.932 | 13.440 | 15.074 | 1.33 ± 0.39 |
| `Go` | 10.495 ± 3.014 | 8.288 | 13.928 | 1.00 |
| `Python` | 14.577 ± 3.341 | 11.174 | 17.854 | 1.39 ± 0.51 |

## Analysis

### Network-Bound Performance
- Network latency dominates this benchmark (~200-300ms per request)
- All implementations are within 40% of each other
- Go has advantage due to mature HTTP client with connection pooling

### CPU Efficiency (User Time)
| Runtime | User Time | System Time |
|---------|-----------|-------------|
| PyAOT | 0.188s | 0.065s |
| Go | 0.013s | 0.013s |
| Python | 1.028s | 0.091s |

**Key Finding:** PyAOT uses **5.5x less CPU** than Python (0.188s vs 1.028s)

### Summary
- PyAOT is ~4% faster than CPython for HTTP requests
- PyAOT uses 82% less CPU time than Python
- Go is fastest overall due to optimized stdlib HTTP client
- PyAOT proves: SSL/TLS, sockets, and HTTP work in pure Zig

## What This Proves

Milestone 1 Complete:
- HTTPS requests work (SSL/TLS handshake)
- Network sockets work (TCP connections)
- HTTP client works (request/response parsing)
- All in pure Zig - no Python runtime
