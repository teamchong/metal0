# PyRegex Implementation Notes

## Goals

1. **Port Rust regex-automata algorithms** - Follow proven approaches
2. **100% Python `re` compatibility** - Match Python behavior exactly
3. **Beat Rust performance** - Use Zig advantages (comptime, SIMD, C allocator)

## Rust regex-automata Architecture

**Sources:**
- [Rust regex-automata GitHub](https://github.com/rust-lang/regex/tree/master/regex-automata)
- [Pike VM implementation](https://github.com/jameysharp/pikevm)
- [Regex engine internals blog](https://burntsushi.net/regex-internals/)

**Key components:**
1. **Thompson NFA** - Sparse states, minimal epsilon transitions
2. **Pike VM** - NFA simulation with O(n) time, O(1) space per regex
3. **Lazy DFA** - Build DFA states on-demand, cache aggressively
4. **Literal optimization** - Boyer-Moore for fast string prefix search

## Python Regex Semantics (CRITICAL - Must Match 100%)

### 1. **Greedy Quantifiers (Default)**
```python
# Python: "a+" matches all "aaa" (greedy)
"aaa" =~ /a+/ → "aaa"
```
**Implementation:** Pike VM explores longest match first

### 2. **Leftmost Match Wins**
```python
# Python: alternation prefers first branch
"cat" =~ /cat|c/ → "cat" (NOT "c")
```
**Implementation:** Pike VM tries branches left-to-right

### 3. **Empty Matches Allowed**
```python
# Python: a* matches empty string
"ab" =~ /a*/ → ["a" at 0, "" at 1, "" at 2]
```
**Implementation:** Pike VM allows zero-length matches

### 4. **Character Classes (ASCII mode)**
```python
\d = [0-9]
\w = [a-zA-Z0-9_]
\s = [ \t\n\v\f\r]  # ASCII whitespace only
```
**Implementation:** Use lookup tables (already in tokenizer/src/allocator_helper.zig)

### 5. **Anchors**
```python
^   = start of string
$   = end of string
\b  = word boundary (before/after \w)
\B  = not word boundary
```
**Implementation:** Check position at match time

### 6. **Capturing Groups**
```python
"abc123" =~ /([a-z]+)(\d+)/ → groups: "abc", "123"
```
**Implementation:** Pike VM tracks capture group spans

## Pike VM Algorithm (From Russ Cox / Rob Pike)

### Core Idea
Simulate NFA by tracking multiple active states simultaneously.

**Complexity:**
- **Time:** O(n × m) where n = text length, m = pattern length
- **Space:** O(m) for state list (reused per character)

### Data Structures

```zig
// Active thread (execution path)
const Thread = struct {
    state: StateId,              // Current NFA state
    captures: [MAX_CAPTURES]Span, // Captured group spans
};

// Sparse set for deduplication
const ThreadList = struct {
    threads: []Thread,
    sparse: []u32,  // state_id -> thread index
    dense: []u32,   // active thread indices
};
```

### Algorithm Steps

```
1. Initialize: Add start state to current thread list
2. For each character in text:
   a. For each active thread:
      - Follow epsilon transitions (splits, assertions)
      - If state matches character, add to next thread list
      - Update capture group spans
   b. Swap current ↔ next thread lists
3. Check if any thread in final list is at match state
4. Return match with captured groups
```

### Epsilon Closure

**Epsilon transitions don't consume input:**
- Split states (alternation, quantifiers)
- Assertions (^, $, \b)

**Implementation:**
```zig
fn addThread(state: StateId, captures: []Span) void {
    // Dedup: if state already visited this round, skip
    if (sparse[state] < dense.len and dense[sparse[state]] == state)
        return;

    // Follow epsilon transitions recursively
    switch (states[state].trans) {
        .split => |targets| {
            for (targets) |t| addThread(t, captures);
        },
        .epsilon => |t| addThread(t, captures),
        else => {
            // Add to thread list
            threads.append(...);
        }
    }
}
```

## Implementation Checklist

### Phase 1: Core Pike VM ✅ (In Progress)
- [x] Thompson NFA construction
- [x] Concatenation, alternation, quantifiers
- [ ] Pike VM state tracking
- [ ] Character matching
- [ ] Epsilon closure
- [ ] Match detection

### Phase 2: Python Compatibility
- [ ] Greedy quantifier semantics
- [ ] Leftmost match (not longest)
- [ ] Empty match handling
- [ ] Capturing groups
- [ ] Character class lookups (\d, \w, \s)
- [ ] Anchors (^, $, \b, \B)

### Phase 3: Optimizations (Beat Rust)
- [ ] Sparse state representation (eliminate epsilons)
- [ ] Lazy DFA with caching
- [ ] SIMD character class matching (@Vector)
- [ ] Boyer-Moore literal prefix search
- [ ] comptime pattern analysis

## Testing Strategy

1. **Unit tests** - Individual NFA operations
2. **Python compatibility suite** - 61 test cases (already created)
3. **Rust parity tests** - Match Rust regex behavior
4. **Performance benchmarks** - Track progress toward beating Rust

## Current Status

**Completed:**
- ✅ Parser (380 lines, 3 tests passing)
- ✅ NFA construction (560 lines, 3 tests passing)
- ✅ Concatenation, alternation, *, +, ?

**Next:**
- ⏳ Pike VM implementation (300-400 lines est.)
- ⏳ Python compatibility testing
- ⏳ Capturing groups
- ⏳ Optimizations

**Progress:** ~20% complete

## Key Differences: Zig vs Rust

### Zig Advantages (How We'll Beat Rust)

1. **comptime** - Pre-compute DFA states for static patterns
   ```zig
   const matcher = comptime buildDFA("fixed pattern");
   ```

2. **@Vector SIMD** - First-class SIMD support
   ```zig
   const Vec16 = @Vector(16, u8);
   const is_digit = (chunk >= '0') & (chunk <= '9');
   ```

3. **C allocator** - 29x faster than GPA (already validated)
   ```zig
   const alloc = allocator_helper.getBenchmarkAllocator(gpa);
   ```

4. **No Result<T,E>** - Simpler error handling
   ```zig
   const match = regex.find(text) catch return null;
   ```

5. **Explicit control** - No hidden allocations or overhead

### Expected Performance Gains

- comptime DFA: +10-15%
- @Vector SIMD: +10-20%
- C allocator: +5-10%
- **Total: 25-45% faster than Rust** (target: 120-150ms vs Rust 171ms)

## References

- [Russ Cox: Regular Expression Matching - The Virtual Machine Approach](https://swtch.com/~rsc/regexp/)
- [Andrew Gallant: Regex engine internals as a library](https://burntsushi.net/regex-internals/)
- [Rust regex-automata source](https://github.com/rust-lang/regex/tree/master/regex-automata)
- [Pike VM educational impl](https://github.com/jameysharp/pikevm)
- Python `re` module documentation
