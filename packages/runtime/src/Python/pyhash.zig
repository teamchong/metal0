/// pyhash - Python Hash Functions
/// Mirrors cpython/Python/pyhash.c
///
/// This module provides hash utility functions for Python objects:
/// - Numeric hashing (integers, floats, complex)
/// - String/bytes hashing (SipHash-2-4)
/// - Pointer hashing
/// - Hash secret management
///
/// The key invariant is: if a == b then hash(a) == hash(b)

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Hash Constants (matching CPython's pyport.h)
// ============================================================================

/// Number of bits in a hash value
pub const HASH_BITS: u6 = 61;

/// Modulus for hash calculations (Mersenne prime 2^61 - 1)
pub const HASH_MODULUS: u64 = (1 << HASH_BITS) - 1;

/// Hash value for positive infinity
pub const HASH_INF: i64 = 314159;

/// Hash value for NaN (pointer-based, but this is a fallback)
pub const HASH_NAN: i64 = 0;

/// Hash value for imaginary unit
pub const HASH_IMAG: i64 = 1000003;

/// Invalid hash value (signals error in CPython)
pub const HASH_INVALID: i64 = -1;

/// Python's Py_hash_t type
pub const HashT = i64;

/// Python's Py_uhash_t type (unsigned)
pub const UHashT = u64;

// ============================================================================
// Hash Secret (for randomized hashing)
// ============================================================================

/// Hash secret structure for SipHash
pub const HashSecret = struct {
    /// SipHash key parts
    k0: u64,
    k1: u64,

    /// FNV seed (for non-SipHash fallback)
    fnv_seed: u64,

    /// Whether the secret has been initialized
    initialized: bool,
};

/// Global hash secret (thread-safe via threadlocal)
threadlocal var hash_secret: HashSecret = .{
    .k0 = 0,
    .k1 = 0,
    .fnv_seed = 0,
    .initialized = false,
};

/// Initialize hash secret with random bytes
pub fn initHashSecret() void {
    if (hash_secret.initialized) return;

    // Get random bytes from OS
    var buf: [24]u8 = undefined;
    std.crypto.random.bytes(&buf);

    hash_secret.k0 = std.mem.readInt(u64, buf[0..8], .little);
    hash_secret.k1 = std.mem.readInt(u64, buf[8..16], .little);
    hash_secret.fnv_seed = std.mem.readInt(u64, buf[16..24], .little);
    hash_secret.initialized = true;
}

/// Get the current hash secret
pub fn getHashSecret() *const HashSecret {
    if (!hash_secret.initialized) {
        initHashSecret();
    }
    return &hash_secret;
}

/// Set hash secret (for reproducible hashing, e.g., PYTHONHASHSEED)
pub fn setHashSecret(k0: u64, k1: u64) void {
    hash_secret.k0 = k0;
    hash_secret.k1 = k1;
    hash_secret.fnv_seed = k0 ^ k1;
    hash_secret.initialized = true;
}

// ============================================================================
// SipHash-2-4 Implementation
// ============================================================================

/// SipHash state
const SipState = struct {
    v0: u64,
    v1: u64,
    v2: u64,
    v3: u64,

    const Self = @This();

    fn init(k0: u64, k1: u64) Self {
        return .{
            .v0 = k0 ^ 0x736f6d6570736575,
            .v1 = k1 ^ 0x646f72616e646f6d,
            .v2 = k0 ^ 0x6c7967656e657261,
            .v3 = k1 ^ 0x7465646279746573,
        };
    }

    fn sipRound(self: *Self) void {
        self.v0 +%= self.v1;
        self.v1 = std.math.rotl(u64, self.v1, 13);
        self.v1 ^= self.v0;
        self.v0 = std.math.rotl(u64, self.v0, 32);
        self.v2 +%= self.v3;
        self.v3 = std.math.rotl(u64, self.v3, 16);
        self.v3 ^= self.v2;
        self.v0 +%= self.v3;
        self.v3 = std.math.rotl(u64, self.v3, 21);
        self.v3 ^= self.v0;
        self.v2 +%= self.v1;
        self.v1 = std.math.rotl(u64, self.v1, 17);
        self.v1 ^= self.v2;
        self.v2 = std.math.rotl(u64, self.v2, 32);
    }

    fn compress(self: *Self, m: u64) void {
        self.v3 ^= m;
        self.sipRound();
        self.sipRound();
        self.v0 ^= m;
    }

    fn finalize(self: *Self) u64 {
        self.v2 ^= 0xff;
        self.sipRound();
        self.sipRound();
        self.sipRound();
        self.sipRound();
        return self.v0 ^ self.v1 ^ self.v2 ^ self.v3;
    }
};

/// Compute SipHash-2-4 of a byte buffer
pub fn sipHash24(data: []const u8) u64 {
    const secret = getHashSecret();
    var state = SipState.init(secret.k0, secret.k1);

    const len = data.len;
    var i: usize = 0;

    // Process 8-byte blocks
    while (i + 8 <= len) : (i += 8) {
        const m = std.mem.readInt(u64, data[i..][0..8], .little);
        state.compress(m);
    }

    // Handle remaining bytes
    var last: u64 = @as(u64, @intCast(len & 0xff)) << 56;
    const remaining = len - i;

    if (remaining >= 7) last |= @as(u64, data[i + 6]) << 48;
    if (remaining >= 6) last |= @as(u64, data[i + 5]) << 40;
    if (remaining >= 5) last |= @as(u64, data[i + 4]) << 32;
    if (remaining >= 4) last |= @as(u64, data[i + 3]) << 24;
    if (remaining >= 3) last |= @as(u64, data[i + 2]) << 16;
    if (remaining >= 2) last |= @as(u64, data[i + 1]) << 8;
    if (remaining >= 1) last |= @as(u64, data[i]);

    state.compress(last);
    return state.finalize();
}

// ============================================================================
// String/Bytes Hashing
// ============================================================================

/// Hash a byte buffer (Python's Py_HashBuffer equivalent)
pub fn hashBuffer(data: []const u8) HashT {
    if (data.len == 0) {
        return 0;
    }

    const h = sipHash24(data);

    // Convert to signed and handle -1 case
    var result: HashT = @bitCast(h & HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }
    return result;
}

/// Hash a string (same as hashBuffer for UTF-8)
pub fn hashString(s: []const u8) HashT {
    return hashBuffer(s);
}

// ============================================================================
// Numeric Hashing
// ============================================================================

/// Hash a double-precision float
/// Mirrors: _Py_HashDouble
pub fn hashDouble(v: f64) HashT {
    // Handle special cases
    if (!std.math.isFinite(v)) {
        if (std.math.isInf(v)) {
            return if (v > 0) HASH_INF else -HASH_INF;
        } else {
            // NaN - return a consistent value
            return HASH_NAN;
        }
    }

    // Handle zero
    if (v == 0.0) {
        return 0;
    }

    // Extract mantissa and exponent
    var e: i32 = undefined;
    var m = std.math.frexp(v);
    const frac = m.significand;
    e = m.exponent;

    const sign: HashT = if (frac < 0) -1 else 1;
    const abs_frac = @abs(frac);

    // Process 28 bits at a time
    var x: UHashT = 0;
    var remaining = abs_frac;

    while (remaining != 0) {
        x = ((x << 28) & HASH_MODULUS) | (x >> (HASH_BITS - 28));
        remaining *= 268435456.0; // 2^28
        e -= 28;
        const y: UHashT = @intFromFloat(remaining);
        remaining -= @floatFromInt(y);
        x += y;
        if (x >= HASH_MODULUS) {
            x -= HASH_MODULUS;
        }
    }

    // Adjust for exponent
    const exp_mod: u6 = @intCast(@mod(@as(i64, e), HASH_BITS));
    x = ((x << exp_mod) & HASH_MODULUS) | (x >> (HASH_BITS - exp_mod));

    var result: HashT = @intCast(x);
    result *= sign;

    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

/// Hash an integer
/// For small integers, the hash is the integer itself
/// For large integers, we reduce modulo HASH_MODULUS
pub fn hashLong(v: i64) HashT {
    if (v == HASH_INVALID) {
        return -2;
    }

    // For values that fit in hash range, return as-is
    if (v >= 0 and v < @as(i64, @intCast(HASH_MODULUS))) {
        return v;
    }

    // Reduce modulo HASH_MODULUS
    var result: HashT = undefined;
    if (v >= 0) {
        result = @intCast(@as(u64, @intCast(v)) % HASH_MODULUS);
    } else {
        // For negative, compute -(|v| mod P)
        const abs_v: u64 = @intCast(-v);
        result = -@as(HashT, @intCast(abs_v % HASH_MODULUS));
    }

    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

/// Hash a complex number
pub fn hashComplex(real: f64, imag: f64) HashT {
    var hash_real = hashDouble(real);
    var hash_imag = hashDouble(imag);

    // Combine using the formula: hash_real + HASH_IMAG * hash_imag
    const combined = hash_real +% @mulWithOverflow(HASH_IMAG, hash_imag)[0];

    var result: HashT = @intCast(@as(u64, @bitCast(combined)) % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Pointer Hashing
// ============================================================================

/// Hash a pointer (for object identity)
pub fn hashPointer(ptr: *const anyopaque) HashT {
    const addr = @intFromPtr(ptr);

    // Rotate to distribute bits (pointers often have aligned low bits)
    const rotated = std.math.rotr(usize, addr, 4);

    var result: HashT = @intCast(rotated % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

/// Raw pointer hash (without -1 adjustment)
pub fn hashPointerRaw(ptr: *const anyopaque) HashT {
    const addr = @intFromPtr(ptr);
    return @intCast(addr % HASH_MODULUS);
}

// ============================================================================
// FNV-1a Hash (fallback/alternative)
// ============================================================================

/// FNV-1a hash constants
const FNV_OFFSET_BASIS: u64 = 14695981039346656037;
const FNV_PRIME: u64 = 1099511628211;

/// Compute FNV-1a hash
pub fn fnvHash(data: []const u8) u64 {
    var hash = FNV_OFFSET_BASIS ^ getHashSecret().fnv_seed;
    for (data) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }
    return hash;
}

// ============================================================================
// Tuple Hashing
// ============================================================================

/// xxHash-based tuple hash multiplier
const TUPLE_HASH_MULT: u64 = 0xc2b2ae3d27d4eb4f;

/// Hash a tuple of hash values
pub fn hashTuple(hashes: []const HashT) HashT {
    var acc: u64 = 0x27d4eb2f165667c5; // Initial accumulator

    for (hashes) |h| {
        const lane: u64 = @bitCast(h);
        acc +%= lane *% TUPLE_HASH_MULT;
        acc = std.math.rotl(u64, acc, 31);
    }

    // Finalize
    acc +%= @as(u64, @intCast(hashes.len)) *% TUPLE_HASH_MULT;
    acc ^= acc >> 33;
    acc *%= 0xff51afd7ed558ccd;
    acc ^= acc >> 33;
    acc *%= 0xc4ceb9fe1a85ec53;
    acc ^= acc >> 33;

    var result: HashT = @intCast(acc % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Frozenset Hashing
// ============================================================================

/// Hash for frozensets (order-independent)
pub fn hashFrozenset(hashes: []const HashT) HashT {
    var hash: u64 = 0;

    for (hashes) |h| {
        // XOR-based combination (order independent)
        const v: u64 = @bitCast(h);
        hash ^= (v ^ (v << 16) ^ 89869747) *% 3644798167;
    }

    // Finalize
    hash = hash *% 69069 +% 907133923;

    var result: HashT = @intCast(hash % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Hash Info (for sys.hash_info)
// ============================================================================

/// Hash algorithm information
pub const HashInfo = struct {
    width: u32,
    modulus: u64,
    inf: i64,
    nan: i64,
    imag: i64,
    algorithm: []const u8,
    hash_bits: u32,
    seed_bits: u32,
};

/// Get hash info (matches sys.hash_info)
pub fn getHashInfo() HashInfo {
    return .{
        .width = 64,
        .modulus = HASH_MODULUS,
        .inf = HASH_INF,
        .nan = HASH_NAN,
        .imag = HASH_IMAG,
        .algorithm = "siphash24",
        .hash_bits = HASH_BITS,
        .seed_bits = 128,
    };
}

// ============================================================================
// Generic Object Hashing
// ============================================================================

/// Hash any Zig value (generic helper)
pub fn hashAny(value: anytype) HashT {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => hashLong(@intCast(value)),
        .float, .comptime_float => hashDouble(@floatCast(value)),
        .bool => if (value) @as(HashT, 1) else @as(HashT, 0),
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice and ptr_info.child == u8) {
                return hashString(value);
            }
            return hashPointer(value);
        },
        .optional => if (value) |v| hashAny(v) else 0,
        else => 0, // Unhashable
    };
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize hash module
pub fn init() void {
    initHashSecret();
}

// ============================================================================
// Tests
// ============================================================================

test "hash constants" {
    try std.testing.expectEqual(@as(u6, 61), HASH_BITS);
    try std.testing.expectEqual(@as(u64, (1 << 61) - 1), HASH_MODULUS);
}

test "hash string" {
    initHashSecret();

    const h1 = hashString("hello");
    const h2 = hashString("hello");
    const h3 = hashString("world");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}

test "hash long" {
    try std.testing.expectEqual(@as(HashT, 0), hashLong(0));
    try std.testing.expectEqual(@as(HashT, 42), hashLong(42));
    try std.testing.expectEqual(@as(HashT, -2), hashLong(-1)); // -1 maps to -2
}

test "hash double" {
    try std.testing.expectEqual(@as(HashT, 0), hashDouble(0.0));
    try std.testing.expectEqual(HASH_INF, hashDouble(std.math.inf(f64)));
    try std.testing.expectEqual(-HASH_INF, hashDouble(-std.math.inf(f64)));

    // Same value should produce same hash
    const h1 = hashDouble(3.14159);
    const h2 = hashDouble(3.14159);
    try std.testing.expectEqual(h1, h2);
}

test "hash tuple" {
    const hashes = [_]HashT{ 1, 2, 3 };
    const h1 = hashTuple(&hashes);
    const h2 = hashTuple(&hashes);
    try std.testing.expectEqual(h1, h2);

    // Different order should produce different hash
    const hashes2 = [_]HashT{ 3, 2, 1 };
    const h3 = hashTuple(&hashes2);
    try std.testing.expect(h1 != h3);
}

test "hash frozenset" {
    const hashes = [_]HashT{ 1, 2, 3 };
    const h1 = hashFrozenset(&hashes);

    // Order should not matter for frozenset
    const hashes2 = [_]HashT{ 3, 1, 2 };
    const h2 = hashFrozenset(&hashes2);
    try std.testing.expectEqual(h1, h2);
}

test "siphash" {
    initHashSecret();

    // Empty string
    const h_empty = sipHash24("");
    try std.testing.expect(h_empty != 0 or hash_secret.k0 == 0);

    // Same input should give same output
    const h1 = sipHash24("test");
    const h2 = sipHash24("test");
    try std.testing.expectEqual(h1, h2);
}

test "hash info" {
    const info = getHashInfo();
    try std.testing.expectEqual(@as(u32, 64), info.width);
    try std.testing.expectEqual(HASH_MODULUS, info.modulus);
    try std.testing.expectEqualStrings("siphash24", info.algorithm);
}
