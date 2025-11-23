# WASM Size Comparison: mvzr vs zig-utils/zig-regex

## Build Results

| Engine | Source Lines | ReleaseSmall (WASM) | ReleaseFast (WASM) | Size Increase |
|--------|--------------|---------------------|-------------------|---------------|
| **mvzr** | 2,503 | **30KB** | **174KB** | Baseline |
| **zig-regex** | 11,077 | **75KB** | **484KB** | +45KB / +310KB |

## Analysis

### ReleaseSmall (-Os, optimize for size)
- **mvzr:** 30KB
- **zig-regex:** 75KB
- **Increase:** +45KB (2.5x larger)

### ReleaseFast (-O3, optimize for speed)
- **mvzr:** 174KB
- **zig-regex:** 484KB
- **Increase:** +310KB (2.8x larger)

## Key Insights

**Source code ratio:**
- zig-regex is 4.4x larger in source lines (11,077 vs 2,503)

**WASM ratio:**
- ReleaseSmall: 2.5x larger (better than source ratio!)
- ReleaseFast: 2.8x larger (Zig dead code elimination working well)

**What's in the extra size:**
- Thompson NFA engine (mvzr uses bytecode VM)
- AST optimization passes
- NFA optimization
- Unicode support
- Named captures
- Lookahead/lookbehind
- Backreferences
- Pattern macros
- Thread safety primitives
- Profiling infrastructure

## Trade-offs

### mvzr (30KB / 174KB)
✅ **Pros:**
- Tiny WASM bundle
- Fast compile times
- Simple codebase
- Good for simple patterns

❌ **Cons:**
- Slower on complex patterns
- Limited features
- Bytecode interpretation overhead

### zig-regex (75KB / 484KB)
✅ **Pros:**
- Much faster (Thompson NFA)
- Full regex features
- Better worst-case guarantees (O(n×m) linear time)
- Production-grade

❌ **Cons:**
- Larger WASM bundle
- More complex codebase
- Longer compile times

## Recommendations

### Use mvzr if:
- Bundle size critical (< 50KB target)
- Simple patterns only (\d+, [a-z]+, etc.)
- Compile time matters
- Minimalist approach preferred

### Use zig-regex if:
- Performance critical (complex patterns)
- Need full regex features (backrefs, lookaround)
- Linear time guarantee required
- 75-484KB acceptable

### Hybrid approach:
- **Fast paths for 80% of cases** (literal strings, single chars, simple classes)
- **mvzr for moderate patterns** (most real-world use)
- **zig-regex for complex patterns** (when needed)
- **Result:** ~40-60KB WASM, fast on common patterns

## Performance Expectations

Based on algorithm differences:

**zig-regex expected speedup:**
- Simple patterns: 1-2x faster (less bytecode overhead)
- Complex patterns: 5-20x faster (NFA vs backtracking)
- Pathological cases: 100-1000x faster (linear time guarantee)

**Worth the 45KB?**
- If patterns are simple → **No** (mvzr sufficient)
- If patterns complex or untrusted → **Yes** (NFA critical)
- If mixed → **Hybrid** (best of both)

## Next Steps

1. Benchmark zig-regex on actual patterns
2. Measure real performance gains
3. Decide: mvzr, zig-regex, or hybrid?
