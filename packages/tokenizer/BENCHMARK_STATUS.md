# Benchmark Status

## Current: 3/5 Libraries Working

**Target: 5 libraries (rs-bpe, tiktoken, TokenDagger, HuggingFace, PyAOT)**

### ✅ Working (3/5)
1. **rs-bpe**: 401ms (fastest, 2.3x faster than tiktoken)
2. **tiktoken**: 936ms (baseline)
3. **HuggingFace**: 4781ms (slowest, reference)

### ❌ Not Working (2/5)
4. **TokenDagger**: C++ extension builds but Python API mismatch
   - Extension built successfully: `tokendagger/_tokendagger_core.cpython-312-darwin.so`
   - Issue: Needs vocab loaded manually (`wrapper.Encoding(name, pattern, vocab, special_tokens)`)
   - Fix: Need to create helper function to load cl100k_base vocab
   - Library paths fixed in Makefile

5. **PyAOT**: 87.9% correct (522/594 tests pass)
   - Issue: Missing regex pre-tokenization
   - Next: Port rs-bpe algorithm + add regex

## How to Run
```bash
./BENCHMARK.sh
```

Auto-builds TokenDagger if needed (with correct library paths).

## TokenDagger Fix Needed
The Makefile has been fixed to include Python libraries:
```make
PYTHON_LIBS = $(shell $(PYTHON_CONFIG) --ldflags --embed 2>/dev/null || $(PYTHON_CONFIG) --ldflags)
```

And library path set in build:
```bash
export LIBRARY_PATH=/opt/homebrew/opt/pcre2/lib:/Users/steven_chong/.local/share/uv/python/cpython-3.12.10-macos-aarch64-none/lib:$LIBRARY_PATH
```

But API usage needs:
```python
# Current (wrong):
enc = wrapper.Encoding.cl100k_base()  # ❌ Not a method

# Correct:
enc = wrapper.Encoding(
    name="cl100k_base",
    pat_str=pattern,
    mergeable_ranks=vocab_dict,
    special_tokens=special_tokens_dict
)
```

Need to load vocab from tiktoken first.
