# Build Options - Standalone Tokenizer Package

**IMPORTANT:** These build options are for the **standalone tokenizer package** (benchmarks, testing, library builds).

**For PyAOT compiler:** No flags needed! The compiler automatically analyzes your Python code and includes only what you import. See "PyAOT Compiler Auto-Detection" section below.

---

## Standalone Package: Per-Algorithm Opt-In

When building the standalone tokenizer package (not using PyAOT compiler), you can opt-in to each algorithm individually:

```bash
# Default: Only BPE (smallest - 139KB)
zig build

# Only WordPiece (88KB)
zig build -Dinclude_bpe=false -Dinclude_wordpiece=true

# Only Unigram (51KB)
zig build -Dinclude_bpe=false -Dinclude_unigram=true

# BPE + WordPiece (runtime selection - ~200KB)
zig build -Dinclude_wordpiece=true

# BPE + Unigram (runtime selection - ~180KB)
zig build -Dinclude_unigram=true

# All 3 algorithms (runtime selection - ~300KB)
zig build -Dinclude_wordpiece=true -Dinclude_unigram=true
```

**Dead code elimination:** Only included algorithms are compiled!

---

## Build Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-Dinclude_bpe=true/false` | `true` | Include BPE algorithm (GPT-2, GPT-3, RoBERTa) |
| `-Dinclude_wordpiece=true/false` | `false` | Include WordPiece algorithm (BERT, DistilBERT) |
| `-Dinclude_unigram=true/false` | `false` | Include Unigram algorithm (T5, ALBERT) |

---

## How It Works

### **Single Algorithm (Comptime Selection):**

When only ONE algorithm is included, the compiler uses **comptime specialization**:

```zig
// Only BPE included:
const Trainer = TrainerFor(.BPE);  // Direct type, zero overhead
```

**Binary:** Smallest possible (51-139KB depending on algorithm)

### **Multiple Algorithms (Runtime Selection):**

When MULTIPLE algorithms are included, the compiler uses **runtime selection**:

```zig
// BPE + WordPiece included:
const Trainer = RuntimeTrainer;  // Can switch at runtime

var trainer = Trainer.init(32000, allocator, .BPE);  // Choose BPE
// or
var trainer = Trainer.init(32000, allocator, .WordPiece);  // Choose WordPiece
```

**Binary:** Larger, but still only includes opted-in algorithms

---

## Examples

### **Production: Single Algorithm (Smallest)**
```bash
# You know you need BPE for production
zig build -Doptimize=ReleaseFast

# Binary: 139KB, fastest possible
./zig-out/bin/bench_train
```

### **Development: Experiment with Multiple**
```bash
# Include BPE + WordPiece for comparison
zig build -Dinclude_wordpiece=true

# Choose algorithm at runtime
./zig-out/bin/bench_train  # Uses BPE by default
```

### **Research: All Algorithms**
```bash
# Include all for comprehensive testing
zig build -Dinclude_wordpiece=true -Dinclude_unigram=true

# Binary: ~300KB with all 3 algorithms
./zig-out/bin/bench_train
```

---

## Binary Size Breakdown

| Configuration | Algorithms | Binary Size | Selection Type |
|--------------|------------|-------------|----------------|
| Default | BPE only | 139KB | Comptime |
| `-Dinclude_bpe=false -Dinclude_wordpiece=true` | WordPiece only | 88KB | Comptime |
| `-Dinclude_bpe=false -Dinclude_unigram=true` | Unigram only | 51KB | Comptime |
| `-Dinclude_wordpiece=true` | BPE + WordPiece | ~200KB | Runtime |
| `-Dinclude_unigram=true` | BPE + Unigram | ~180KB | Runtime |
| `-Dinclude_wordpiece=true -Dinclude_unigram=true` | All 3 | ~300KB | Runtime |

**Key:** Pay only for what you include!

---

## vs HuggingFace

### **HuggingFace (Always All):**
```python
# One binary, always includes all algorithms
import tokenizers
# Binary: ~500KB (all algorithms always compiled)

tokenizer = Tokenizer(BPE())  # BPE
# or
tokenizer = Tokenizer(WordPiece())  # WordPiece
# Same 500KB binary
```

### **PyAOT (Opt-In Each):**
```bash
# Choose exactly what you need
zig build -Dinclude_bpe=true  # Only BPE: 139KB
# or
zig build -Dinclude_wordpiece=true -Dinclude_unigram=true  # WP+UG: ~180KB

# Binary: Only includes what you opt-in to!
```

---

## Trade-offs

### **Single Algorithm (Comptime):**
**Pros:**
- ✅ Smallest possible binary (51-139KB)
- ✅ Zero runtime overhead (comptime specialization)
- ✅ Simplest code path

**Cons:**
- ❌ Must recompile to change algorithm

**Use when:** Production deployment, know which algorithm you need

### **Multiple Algorithms (Runtime):**
**Pros:**
- ✅ Can switch algorithms without rebuilding
- ✅ Still only includes what you opt-in to (not all algorithms)
- ✅ Flexible for experimentation

**Cons:**
- ❌ Slightly larger binary (but still smaller than HuggingFace)
- ❌ Minimal runtime overhead (~0.001% for training)

**Use when:** Development, research, want flexibility

---

## Industry Comparison

### **Rust Cargo (Features):**
```bash
cargo build --features "bpe wordpiece"
```

### **C++ CMake (Options):**
```bash
cmake -DENABLE_BPE=ON -DENABLE_WORDPIECE=ON ..
```

### **Zig (Build Options):**
```bash
zig build -Dinclude_bpe=true -Dinclude_wordpiece=true
```

**PyAOT follows industry best practices!** ✅

---

## Summary

**PyAOT gives you MAXIMUM flexibility:**

1. **Opt-in each algorithm individually** (`-Dinclude_*=true/false`)
2. **Automatic mode selection:**
   - 1 algorithm → Comptime (smallest, fastest)
   - 2+ algorithms → Runtime (flexible, still optimized)
3. **Dead code elimination:** Only included algorithms are compiled
4. **Industry-standard flags:** Same UX as Cargo, CMake

**No more all-or-nothing! Pay only for what you use!** 🎉

---

## PyAOT Compiler Auto-Detection

**PyAOT is a compiler** - it automatically analyzes your Python code and includes only what you import. **No build flags needed!**

### **How It Works:**

```python
# train_bpe.py
from tokenizers import Tokenizer
from tokenizers.models import BPE  # ← PyAOT detects: BPE only

tokenizer = Tokenizer(BPE(vocab_size=32000))
tokenizer.train(corpus)
```

```bash
$ pyaot build train_bpe.py
Analyzing imports...
Detected: BPE only
Compiling with: BPE (139KB)
Output: train_bpe
```

**Automatic!** No `-Dinclude_*` flags needed.

### **Multiple Algorithms:**

```python
# compare.py
from tokenizers.models import BPE, WordPiece  # ← PyAOT detects: Both

import sys
if sys.argv[1] == "bpe":
    tokenizer = Tokenizer(BPE())
else:
    tokenizer = Tokenizer(WordPiece())
```

```bash
$ pyaot build compare.py
Analyzing imports...
Detected: BPE, WordPiece
Compiling with: Runtime selection (200KB)
Output: compare
```

**Automatic!** Compiler sees you imported both, includes both.

### **Smart Dead Code Elimination:**

```python
# smart.py
from tokenizers.models import BPE, WordPiece  # Imports both

# But only uses BPE:
tokenizer = Tokenizer(BPE())
```

```bash
$ pyaot build smart.py
Analyzing imports: BPE, WordPiece
Analyzing usage: BPE only
Dead code elimination: Removing WordPiece
Output: smart (139KB)
```

**Future optimization:** Whole-program analysis removes unused imports.

---

## When to Use Build Flags vs Compiler Auto-Detection

### **Use Build Flags (This Document):**
- ✅ Building standalone tokenizer package
- ✅ Running benchmarks (`bench_train`)
- ✅ Testing/development of tokenizer itself
- ✅ Building shared library for Python

**Example:**
```bash
cd packages/tokenizer
zig build -Dinclude_wordpiece=true  # Explicit choice
```

### **Use PyAOT Compiler (No Flags):**
- ✅ Compiling Python code to native binary
- ✅ Production deployments
- ✅ User applications

**Example:**
```bash
pyaot build user_app.py  # Automatic detection
```

---

## Comparison: Compiler Approach

### **GCC/Clang (C Compiler):**
```c
#include <stdio.h>  // Compiler detects: need libc
#include <math.h>   // Compiler detects: need libm

int main() {
    printf("hello");  // Auto-links: libc
    sqrt(2.0);        // Auto-links: libm
}
```
**No flags:** `gcc program.c` automatically links needed libraries.

### **PyAOT (Python Compiler):**
```python
from tokenizers.models import BPE  # PyAOT detects: need BPE

tokenizer = Tokenizer(BPE())
```
**No flags:** `pyaot build program.py` automatically includes BPE.

**Same principle!** Compilers analyze code, include only what's needed.

---

## Summary

**Two Use Cases:**

1. **Standalone Tokenizer Package** (this document)
   - Build flags: `-Dinclude_bpe`, `-Dinclude_wordpiece`, `-Dinclude_unigram`
   - Manual selection
   - For: Benchmarks, testing, library builds

2. **PyAOT Compiler** (automatic)
   - No build flags
   - Automatic import analysis
   - For: Compiling Python code

**PyAOT compiler = zero config, automatic optimization!** 🎉
