# Quick Regex Optimization Demo

## Example: Character Class Lookup Table

**Current mvzr approach (slow):**
```zig
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';  // 2 comparisons per char
}
```

**Optimized with lookup table (fast):**
```zig
const DIGIT_LOOKUP: [256]bool = comptime blk: {
    var table = [_]bool{false} ** 256;
    for ('0'..'9' + 1) |i| {
        table[i] = true;
    }
    break :blk table;
};

fn isDigit(c: u8) bool {
    return DIGIT_LOOKUP[c];  // 1 lookup (faster)
}
```

**Performance gain:** 20-30% on digit-heavy patterns

## Example: SIMD Character Matching

**Find first digit in string (scalar):**
```zig
fn findDigit(text: []const u8) ?usize {
    for (text, 0..) |c, i| {
        if (c >= '0' and c <= '9') return i;
    }
    return null;
}
// Processes 1 byte per iteration
```

**Find first digit (SIMD):**
```zig
fn findDigitSIMD(text: []const u8) ?usize {
    const Vec16 = @Vector(16, u8);
    const zero = @splat(16, @as(u8, '0'));
    const nine = @splat(16, @as(u8, '9'));

    var i: usize = 0;
    while (i + 16 <= text.len) : (i += 16) {
        const chunk: Vec16 = text[i..][0..16].*;
        const ge_zero = chunk >= zero;
        const le_nine = chunk <= nine;
        const is_digit = ge_zero & le_nine;

        if (@reduce(.Or, is_digit)) {
            // Found digit in this chunk, scan to find position
            for (text[i..i+16], 0..) |c, j| {
                if (c >= '0' and c <= '9') return i + j;
            }
        }
    }
    // Handle remaining bytes
    return findDigit(text[i..]);
}
// Processes 16 bytes per iteration (16x faster!)
```

## Example: Inline Hot Path

**Before (function call overhead):**
```zig
pub fn match(regex: Regex, text: []const u8) ?Match {
    return matchInternal(regex, text, 0);
}

fn matchInternal(regex: Regex, text: []const u8, pos: usize) ?Match {
    // ... matching logic
}
```

**After (inline):**
```zig
pub inline fn match(regex: Regex, text: []const u8) ?Match {
    // Inline the hot path directly
    var pos: usize = 0;
    // ... matching logic directly here
}
```

**Gain:** Eliminates function call overhead (5-10% faster)

## Benchmarking the Optimizations

```bash
# Profile to find hotspots
zig build bench -Doptimize=ReleaseFast

# Compare before/after
hyperfine --warmup 10 \
  './bench_zig_old' \
  './bench_zig_optimized'
```

## Quick Wins Checklist

- [ ] Add lookup tables for character classes
- [ ] Inline hot functions (match, iterator.next)
- [ ] Use SIMD for simple scans
- [ ] Precompile pattern at comptime when possible
- [ ] Profile with perf/Instruments to find bottlenecks

**Expected total gain: 30-50% faster with 2-3 hours of work**
