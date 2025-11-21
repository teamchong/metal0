# Correctness-First Implementation Strategy

## Philosophy

**Don't invent algorithms - copy proven ones, optimize with Zig.**

### ❌ Wrong Approach (what we were doing)
- Invent new SIMD optimizations
- Hope they're correct
- Can't verify easily
- **Result: Fast but possibly wrong**

### ✅ Right Approach (user's suggestion)
1. **Copy exact algorithm** from rs-bpe/tiktoken (proven correct)
2. **Port to Zig** line-by-line, verify matches
3. **Add Zig advantages:**
   - `comptime` for zero-cost abstractions
   - `@setRuntimeSafety(false)` for speed
   - SIMD where reference uses it
   - Better memory layout
4. **Verify correctness** on every change
5. **Then benchmark**

**Result: Correct AND fast**

---

## Reference Selection

**Primary: rs-bpe (Rust)**
- ✅ Fastest (462ms vs tiktoken 1060ms)
- ✅ 100% correct (we verified)
- ✅ Most optimized recent code
- ✅ Open source, readable

**Secondary: tiktoken (Rust)**
- ✅ OpenAI official reference
- ✅ Most widely used
- ✅ Good fallback if rs-bpe unclear

**Tertiary: HuggingFace (Rust)**
- ✅ Industry standard
- ✅ Well documented

---

## Implementation Plan

### Phase 1: Training (Copy rs-bpe/HuggingFace)
1. **Read:** rs-bpe training code
2. **Port:** Exact algorithm to Zig
3. **Verify:** Train on test set, compare vocab/merges
4. **Optimize:** Add Zig comptime/unsafe where safe
5. **Test:** 100% match with reference

### Phase 2: Encoding (Copy rs-bpe)
1. **Read:** rs-bpe BPE encode implementation
2. **Port:** Exact algorithm to Zig
3. **Verify:** Test all 583 benchmark texts
4. **Optimize:** Add Zig advantages
5. **Test:** 100% match on all tests

### Phase 3: Zig Optimizations (After 100% correctness)

**Only add optimizations that preserve correctness:**

1. **comptime**
   ```zig
   // Reference (runtime):
   const vec_size = if (has_avx512) 32 else 16;

   // Zig (comptime):
   const vec_size = comptime blk: {
       if (@hasDecl(builtin.cpu.features, "avx512f"))
           break :blk 32
       else
           break :blk 16;
   };
   ```

2. **@setRuntimeSafety(false)**
   ```zig
   // Only in hot loops, after correctness verified
   fn encode(text: []const u8) ![]u32 {
       @setRuntimeSafety(false);
       // ... exact same logic as reference
   }
   ```

3. **SIMD** (if reference uses it)
   ```zig
   // Only where reference already uses SIMD
   // Copy their algorithm, just use Zig's @Vector
   ```

4. **Better memory layout**
   ```zig
   // Cache-aligned, packed structs
   // But same algorithm as reference
   ```

---

## Verification Strategy

**After each change:**

1. **Unit test:** Specific function output
2. **Integration test:** Full encode/decode cycle
3. **Benchmark test:** All 583 texts + edge cases
4. **Regression test:** Compare with previous known-good output

**100% match required to proceed.**

---

## Agent Tasks

### Agent 1: Study rs-bpe Training
- Read rs-bpe training source code
- Document algorithm step-by-step
- Identify optimizations they use
- Create Zig port plan

### Agent 2: Study rs-bpe Encoding
- Read rs-bpe BPE encode source
- Document algorithm step-by-step
- Identify optimizations they use
- Create Zig port plan

### Agent 3: Create Verification Tests
- Test harness for 583 texts
- Edge case tests
- Comparison with rs-bpe output
- Automated correctness checks

---

## Expected Results

**Correctness:** 100% (copying proven algorithm)

**Speed:** Should match or beat rs-bpe because:
- Zig comptime eliminates runtime checks
- `@setRuntimeSafety(false)` removes bounds checks
- Better memory layout (stack vs heap)
- Same SIMD as reference (or better)

**Confidence:** HIGH (algorithm is proven, only implementation risk)

---

## Next Steps

1. ✅ Stop current optimization work
2. 📖 Study rs-bpe source code
3. ✍️ Port algorithm to Zig (exact logic)
4. ✅ Verify 100% correctness
5. ⚡ Add Zig optimizations (preserving correctness)
6. 🏆 Benchmark (should beat rs-bpe!)
