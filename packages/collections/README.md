# Generic Collections - Comptime Specialization

This directory contains **generic, comptime-specialized implementations** of common data structures.

## Philosophy

**Write once, specialize many!**

All implementations use Zig's comptime system to:
- Generate optimal code for each config
- Eliminate unused fields (zero overhead)
- Catch bugs at compile-time (not runtime)
- Share code between similar types

## Implementations

### buffer_impl.zig (350 lines)
Generic buffer for ALL buffer types:
- Simple 1D buffers
- Multi-dimensional arrays (NumPy)
- Read-only buffers
- Typed buffers (i32, f64, etc.)

**Usage:**
```zig
const SimpleBuffer = BufferImpl(SimpleBufferConfig);
const NDBuffer = BufferImpl(NDArrayBufferConfig);
```

### set_impl.zig (200 lines)
Generic set that **reuses dict_impl**!

**Key insight:** Set = Dict with void values

**Usage:**
```zig
const IntSet = SetImpl(NativeIntSetConfig);
var set = try IntSet.init(allocator);
try set.add(42);
```

### iterator_impl.zig (220 lines)
Generic iterator for ALL container types:
- PyListIter, PyTupleIter, PySetIter
- Native slices (immutable and mutable)
- Range iterators

**Usage:**
```zig
const SliceIter = IteratorImpl(SliceIterConfig(i64));
var iter = SliceIter.init(&data);
while (iter.next()) |item| { ... }
```

### dict_impl.zig (existing)
Generic hash table implementation.

Used by set_impl.zig!

### list_impl.zig (existing)
Generic dynamic array.

### tuple_impl.zig (existing)
Generic fixed-size array.

## Comptime Techniques

### 1. Conditional Fields
```zig
ndim: if (Config.multi_dimensional) isize else void,
```
Field only exists when Config enables it!

### 2. Compile-Time Errors
```zig
comptime {
    if (!Config.feature) {
        @compileError("Config doesn't support feature");
    }
}
```
Prevent misuse at compile-time!

### 3. Type Reuse
```zig
const DictConfig = struct {
    pub const ValueType = void; // Set = Dict with void!
};
```
Reuse existing implementations!

## Code Size Wins

**Traditional approach (manual specialization):**
- Simple buffer: 200 lines
- ND buffer: 400 lines
- Readonly buffer: 200 lines
- Set: 400 lines
- List iter: 100 lines
- **Total: 1,300 lines**

**Comptime approach (generic implementations):**
- buffer_impl: 350 lines (ALL configs!)
- set_impl: 200 lines (reuses dict!)
- iterator_impl: 220 lines (ALL types!)
- **Total: 770 lines**

**SAVINGS: 530 lines (41% reduction!)**

## Testing

See `packages/c_interop/tests/test_comptime_wins.zig` for comprehensive integration tests.

Tests ensure all configs work correctly and demonstrate the comptime wins.

## Performance

**Zero runtime cost!**

All comptime decisions are resolved at compile-time:
- No vtables
- No function pointers
- No runtime type checks
- Compiler generates optimal code for each config

## Usage Guidelines

1. **Think generic first:** Before writing, ask "Can I make this generic?"
2. **Reuse aggressively:** Check if existing generic implementation fits
3. **Comptime is free:** Use it liberally for optimization
4. **Test comprehensively:** Integration tests ensure all configs work

## Next Steps

These generic implementations enable:
- NumPy array support (using buffer_impl)
- Efficient collections (using dict/set/list)
- Python iterators (using iterator_impl)

**All with minimal code and zero runtime cost!** 🎉
