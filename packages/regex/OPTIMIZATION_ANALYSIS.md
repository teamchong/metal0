# Regex Performance Analysis: Why Python's C `re` is Faster

## Current State

**Python (re module):** 917ms total
**PyAOT/Zig (mvzr):** 1579ms total (1.72x slower)

## Root Causes

### 1. Algorithm Differences

**Python `re` (C implementation):**
- Hybrid NFA/DFA engine with backtracking
- Pattern compilation with aggressive optimization
- DFA caching for repeated patterns
- Specialized fast paths for common cases
- 30+ years of optimization

**mvzr (Pure Zig bytecode VM):**
- Simple bytecode interpreter
- No DFA conversion
- No pattern optimization
- Designed for simplicity, not speed
- Interpretation overhead on every operation

### 2. Where mvzr Loses Performance

**Bytecode Interpretation Overhead:**
```zig
// mvzr executes bytecode in a loop
while (pc < ops.len) {
    switch (ops[pc]) {
        .Char => { /* match single char */ },
        .CharSet => { /* check set */ },
        // Each operation = indirect jump + branch
    }
    pc += 1;  // Overhead on EVERY character
}
```

**Python `re` direct execution:**
```c
// Compiled to optimized machine code
if (*str == 'a') goto match;  // Direct comparison
// SIMD for character classes
// Inline critical paths
```

**Cost per operation:**
- mvzr bytecode: ~5-10 CPU cycles (dispatch overhead)
- Python re: ~1-2 CPU cycles (direct execution)

### 3. Optimization Gaps

| Optimization | Python `re` | mvzr | Impact |
|--------------|-------------|------|--------|
| DFA conversion | ✅ | ❌ | 10-50x |
| Pattern compilation | ✅ | ✅ | - |
| SIMD for char matching | ✅ | ❌ | 4-8x |
| Inline hot paths | ✅ | ❌ | 2-3x |
| Branch prediction hints | ✅ | ❌ | 1.5-2x |
| Specialized fast paths | ✅ | ❌ | 2-10x |

## Optimization Opportunities

### Option 1: Switch to NFA-based Engine (Recommended)

Use `zig-utils/zig-regex` instead of `mvzr`:
- Thompson NFA construction (linear time guarantee)
- DFA conversion for hot patterns
- Similar algorithm to Python's `re`
- Expected: 2-5x faster than mvzr

**Cost:** More complex, larger binary (~10KB vs ~2KB)

### Option 2: Optimize mvzr (Medium effort)

**Quick wins (30-50% faster):**

1. **Inline hot operations:**
```zig
// Before: function call overhead
fn matchChar(c: u8, target: u8) bool { return c == target; }

// After: inline in hot loop
inline for (pattern) |c| {
    if (text[pos] == c) { /* match */ }
}
```

2. **SIMD for character classes:**
```zig
// Check if char in [a-zA-Z0-9] using SIMD
const Vec = @Vector(16, u8);
const ranges = Vec{...};
const matches = @reduce(.Or, text_vec >= ranges_low and text_vec <= ranges_high);
```

3. **Precompute character class lookups:**
```zig
// Before: linear scan for each char
for (char_set) |c| if (input == c) return true;

// After: 256-byte lookup table
const lookup: [256]bool = comptime buildLookup(char_set);
if (lookup[input]) return true;
```

**Expected gain:** 1.3-1.5x faster (mvzr: 1579ms → ~1050ms)

### Option 3: Hybrid Approach (Best of both)

**Use different engines for different patterns:**
```zig
// Simple patterns: optimized fast path
if (isSimplePattern(pattern)) {
    return fastMatch(pattern, text);  // Hand-optimized
}

// Complex patterns: NFA engine
return nfaMatch(pattern, text);
```

**Fast paths:**
- Literal strings: Boyer-Moore or memchr
- Single char: SIMD scan
- Character classes: Lookup table
- Anchored patterns: Direct comparison

**Expected gain:** 2-3x faster on common patterns

## Practical Recommendations

### Short-term (This week)

1. **Profile mvzr** to find hotspots:
```bash
zig build bench -Doptimize=ReleaseFast -Dcpu=baseline -fprofile-generate
# Run benchmarks
llvm-profdata merge -o default.profdata default_*.profraw
zig build bench -Doptimize=ReleaseFast -fprofile-use=default.profdata
```

2. **Add lookup table for character classes** (30 min, 20-30% gain)

3. **Inline critical functions** (1 hour, 10-15% gain)

### Medium-term (This month)

1. **Evaluate zig-utils/zig-regex:**
   - Test on our patterns
   - Measure performance vs mvzr
   - Check binary size impact

2. **Implement fast paths:**
   - Literal string matching (Boyer-Moore)
   - Single character SIMD scan
   - Simple patterns direct execution

### Long-term (Next quarter)

1. **Hybrid regex engine:**
   - Pattern analyzer (determines complexity)
   - Fast path for 80% of cases
   - NFA fallback for complex patterns

2. **JIT compilation (advanced):**
   - Compile hot patterns to native code
   - Requires runtime code generation
   - 10-100x speedup possible

## Why Digits Pattern is Faster in Zig

**Pattern:** `\d+` (one or more digits)

**Python (11.4µs):**
- Checks character class [0-9] via function call
- Backtracking on '+' quantifier

**Zig/mvzr (8.0µs) - 1.4x faster:**
- Simple bytecode: `DIGIT` operation + loop
- No function call overhead (inlined)
- Tight loop over text

**Why Zig wins here:**
- Simple pattern benefits from tight loop
- No complex backtracking needed
- Bytecode dispatch overhead minimized
- Good branch prediction

## Conclusion

**Yes, we have full control to optimize!** Zig can match or beat C performance.

**The gap isn't language - it's algorithm:**
- Python uses highly optimized NFA/DFA hybrid
- mvzr uses simple bytecode VM
- Both compile to machine code
- mvzr's algorithm is fundamentally slower

**To match Python:**
1. Switch to NFA-based engine (zig-utils/zig-regex)
2. Add SIMD optimizations
3. Implement DFA caching
4. Profile and inline hot paths

**Expected result:** Match or beat Python's performance with proper optimization.

**Trade-off:** Complexity vs speed vs binary size
- mvzr: 2.5KB, simple, 1.7x slower
- Optimized NFA: ~15KB, complex, potentially faster
- Choose based on use case
