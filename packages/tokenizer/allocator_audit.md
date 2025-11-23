# Allocator Usage Audit

## ✅ Files Using allocator_helper (CORRECT - 2 files)

- `bench_pyaot_json_parse_fast.zig`
- `bench_pyaot_json_stringify_fast.zig`

## ❌ Files Using std.heap.c_allocator Directly (BREAKS WASM - 6 files)

1. `src/bench_native.zig` - Main benchmark
2. `src/main.zig` - CLI entry point
3. `src/tokenizer.zig` - Core tokenizer (line 27 comment mentions it)
4. `test_100_percent_correct.zig` - Correctness test
5. `bench_pyaot_json_stringify_c.zig` - Old JSON benchmark
6. `bench_pyaot_json_parse_c.zig` - Old JSON benchmark

## ⚠️ Files Using gpa.allocator() Directly (29x SLOWER - 20 files)

**Benchmarks (HIGH PRIORITY):**
1. `src/bench_native.zig` (also uses c_allocator)
2. `src/bench_allocations_detailed.zig`
3. `src/bench_profile_detailed.zig`
4. `src/bench_encoding_only.zig`
5. `src/bench_allocations.zig`
6. `src/bench_chunks.zig`
7. `src/bench_with_counts.zig`
8. `src/bench_code.zig`
9. `src/bench_train.zig`

**Tests:**
10. `src/test_splitter.zig`
11. `src/test_correctness.zig`
12. `test_100_percent_correct.zig`
13. `test_pyaot_parse.zig`

**Production Code (CRITICAL):**
14. `src/python.zig` - Python bindings (6 functions!)
15. `src/main.zig` - CLI entry point

**Examples:**
16. `example_features.zig`
17. `src/comptime_ac.zig`

**Old/Failed Experiments (LOW PRIORITY):**
18. `bench_pyaot_json_parse_arena.zig` - Failed arena experiment
19. `bench_pyaot_json_stringify_opt.zig` - Failed optimization
20. `bench_pyaot_json_parse_opt.zig` - Failed optimization
21. `bench_pyaot_json_stringify.zig` - Old baseline (before optimization)
22. `bench_pyaot_json_parse.zig` - Old baseline (before optimization)

## Summary

- **CORRECT:** 2 files (10%)
- **NEEDS FIX:** 24+ files (90%)

## Priority Fix Order

1. **HIGH:** All `src/bench_*.zig` files (9 files) - Performance benchmarks must use optimal allocator
2. **HIGH:** `src/python.zig` - Production Python bindings (6 functions)
3. **HIGH:** `src/main.zig` - CLI entry point
4. **MEDIUM:** `src/tokenizer.zig` - Core tokenizer
5. **MEDIUM:** Test files (4 files)
6. **LOW:** Old/failed experiments (5 files) - Can delete instead of fixing
7. **LOW:** Examples (2 files)
