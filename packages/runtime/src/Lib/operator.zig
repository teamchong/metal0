//! CPython source: Lib/operator.py
//!
//! Provides functions corresponding to Python's intrinsic operators.
//! These are useful for functional programming and with functions like map/reduce.
//!
//! Mirrors: CPython Lib/operator.py
//!
//! NOTE: Comparison operations dispatch to comparison_ops.zig for common types
//! to reduce monomorphization. Use runtime.comparison_ops.eqI64 etc. directly
//! in generated code for known concrete types.

const std = @import("std");
const comparison = @import("../runtime/comparison.zig");
const type_predicates = @import("../runtime/type_predicates.zig");
const PyValue = @import("../Objects/object.zig").PyValue;
const float_ops = @import("../runtime/float_ops/arithmetic.zig");
const operator_ops = @import("../runtime/operator_ops.zig");

// ============================================================================
// Comparison Operations
// THE ONE SOURCE OF TRUTH: All comparisons go through runtime/comparison.zig
// ============================================================================

/// Less than: a < b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn lt(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.lessThan(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return pv_a.lt(pv_b);
}

/// Less than or equal: a <= b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn le(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.lessThanOrEqual(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return pv_a.le(pv_b);
}

/// Equal: a == b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn eq(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.equal(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return pv_a.eql(pv_b);
}

/// Not equal: a != b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn ne(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.notEqual(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return !pv_a.eql(pv_b);
}

/// Greater than or equal: a >= b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn ge(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.greaterThanOrEqual(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return pv_a.ge(pv_b);
}

/// Greater than: a > b
/// Supports cross-type comparison by converting to PyValue when types differ
pub fn gt(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == B) {
        return comparison.greaterThan(a, b);
    }
    // Cross-type: convert both to PyValue and use vtable-based comparison
    const pv_a = PyValue.from(a);
    const pv_b = PyValue.from(b);
    return pv_a.gt(pv_b);
}

// ============================================================================
// Logical Operations
// ============================================================================

/// Logical not: not a
pub fn not_(a: anytype) bool {
    const T = @TypeOf(a);
    if (T == bool) {
        return !a;
    }
    // For numeric types, 0 is falsy
    if (@typeInfo(T) == .int or @typeInfo(T) == .float) {
        return a == 0;
    }
    // For optionals, null is falsy
    if (@typeInfo(T) == .optional) {
        return a == null;
    }
    return false;
}

/// Logical truth value
pub fn truth(a: anytype) bool {
    return !not_(a);
}

// ============================================================================
// Arithmetic Operations
// ============================================================================

/// Absolute value: abs(a)
pub fn abs(a: anytype) @TypeOf(a) {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .int) {
        return if (a < 0) -a else a;
    }
    if (@typeInfo(T) == .float) {
        return @abs(a);
    }
    return a;
}

/// Addition: a + b
pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a + b;
}

/// Subtraction: a - b
pub fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a - b;
}

/// Multiplication: a * b
pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a * b;
}

/// True division: a / b (floating point)
pub fn truediv(a: anytype, b: @TypeOf(a)) f64 {
    const af: f64 = @floatFromInt(a);
    const bf: f64 = @floatFromInt(b);
    return af / bf;
}

/// Floor division: a // b
pub fn floordiv(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return @divFloor(a, b);
}

/// Modulo: a % b
/// For floats, uses Python semantics with proper signed zero handling
pub fn mod(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const T = @TypeOf(a);
    const info = @typeInfo(T);
    // For floats, use Python's modulo semantics (handles signed zeros)
    if (type_predicates.isFloatInfo(info)) {
        return @floatCast(float_ops.pyFloatMod(a, b));
    }
    // For integers, use Zig's builtin mod
    return @mod(a, b);
}

const PythonError = @import("../runtime/exceptions.zig").PythonError;

/// Check if type looks like PyComplex (struct with real and imag f64 fields)
fn isComplexLike(comptime T: type, comptime info: std.builtin.Type) bool {
    if (info != .@"struct") return false;
    if (!@hasField(T, "real") or !@hasField(T, "imag")) return false;
    const RealType = @TypeOf(@field(@as(T, undefined), "real"));
    const ImagType = @TypeOf(@field(@as(T, undefined), "imag"));
    return (RealType == f64 or RealType == comptime_float) and
        (ImagType == f64 or ImagType == comptime_float);
}

/// Polymorphic modulo for unknown types - raises TypeError for complex
pub fn modCall(a: anytype, b: anytype) PythonError!i64 {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);

    // Check for PyComplex struct
    if (isComplexLike(AType, a_info) or isComplexLike(BType, b_info)) {
        return PythonError.TypeError;
    }

    // Numeric types
    if (type_predicates.isIntInfo(a_info) and type_predicates.isIntInfo(b_info)) {
        return @mod(@as(i64, a), @as(i64, b));
    }

    return PythonError.TypeError;
}

/// Polymorphic floordiv for unknown types - raises TypeError for complex
pub fn floordivCall(a: anytype, b: anytype) PythonError!i64 {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);

    // Check for PyComplex struct
    if (isComplexLike(AType, a_info) or isComplexLike(BType, b_info)) {
        return PythonError.TypeError;
    }

    // Numeric types
    if (type_predicates.isIntInfo(a_info) and type_predicates.isIntInfo(b_info)) {
        return @divFloor(@as(i64, a), @as(i64, b));
    }

    return PythonError.TypeError;
}

/// Convert any numeric type to i64 for divmod result
fn convertToI64(value: anytype) i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    return switch (info) {
        .int, .comptime_int => @as(i64, @intCast(value)),
        .float, .comptime_float => @as(i64, @intFromFloat(value)),
        else => 0, // Fallback for unexpected types
    };
}

/// Polymorphic divmod for unknown types - raises TypeError for complex
/// Returns tuple (a // b, a % b) as .{ i64, i64 }
/// Supports class instances with __floordiv__ and __mod__ methods
pub fn divmodCall(a: anytype, b: anytype) PythonError!struct { i64, i64 } {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);

    // Check for PyComplex struct - divmod on complex raises TypeError
    if (isComplexLike(AType, a_info) or isComplexLike(BType, b_info)) {
        return PythonError.TypeError;
    }

    // Handle class instances (pointers to structs with __floordiv__/__mod__)
    if (a_info == .pointer and a_info.pointer.size == .one) {
        const ChildA = a_info.pointer.child;
        if (@typeInfo(ChildA) == .@"struct") {
            if (@hasDecl(ChildA, "__floordiv__") and @hasDecl(ChildA, "__mod__")) {
                // Class methods may require an allocator parameter
                // Use c_allocator as a fallback (same as __global_allocator in generated code)
                const floordiv_result = a.__floordiv__(std.heap.c_allocator, b) catch return PythonError.TypeError;
                const mod_raw = a.__mod__(std.heap.c_allocator, b) catch return PythonError.TypeError;
                // Convert mod result to i64 - may be f64 if using pyFloatMod, or i64 from @mod
                const mod_result = convertToI64(mod_raw);
                return .{ convertToI64(floordiv_result), mod_result };
            }
        }
    }

    // Handle reverse case: divmod(int, ClassInstance) calls __rfloordiv__/__rmod__
    if (b_info == .pointer and b_info.pointer.size == .one) {
        const ChildB = b_info.pointer.child;
        if (@typeInfo(ChildB) == .@"struct") {
            if (@hasDecl(ChildB, "__rfloordiv__") and @hasDecl(ChildB, "__rmod__")) {
                // Reverse methods: b.__rfloordiv__(a), b.__rmod__(a)
                const floordiv_result = b.__rfloordiv__(std.heap.c_allocator, a) catch return PythonError.TypeError;
                const mod_raw = b.__rmod__(std.heap.c_allocator, a) catch return PythonError.TypeError;
                // Convert mod result to i64 - may be f64 if using pyFloatMod, or i64 from @mod
                const mod_result = convertToI64(mod_raw);
                return .{ convertToI64(floordiv_result), mod_result };
            }
        }
    }

    // Numeric types
    if (type_predicates.isIntInfo(a_info) and type_predicates.isIntInfo(b_info)) {
        const ai: i64 = @as(i64, a);
        const bi: i64 = @as(i64, b);
        return .{ @divFloor(ai, bi), @mod(ai, bi) };
    }

    // Handle floats - Python's divmod on floats returns (floor division, modulo)
    if (type_predicates.isFloatInfo(a_info) or type_predicates.isFloatInfo(b_info)) {
        const af: f64 = if (type_predicates.isFloatInfo(a_info)) @as(f64, @floatCast(a)) else @as(f64, @floatFromInt(a));
        const bf: f64 = if (type_predicates.isFloatInfo(b_info)) @as(f64, @floatCast(b)) else @as(f64, @floatFromInt(b));
        const q = @floor(af / bf);
        const r = af - q * bf;
        return .{ @intFromFloat(q), @intFromFloat(r) };
    }

    return PythonError.TypeError;
}

/// Negation: -a
pub fn neg(a: anytype) @TypeOf(a) {
    return -a;
}

/// Positive: +a
pub fn pos(a: anytype) @TypeOf(a) {
    return a;
}

/// Power: a ** b
/// Returns PyValue which can be either float or complex
/// Python: (-2.0) ** 0.5 returns complex, 4.0 ** 0.5 returns float
/// NOTE: Returns PyValue (not PyPowResult) for O(1) type compatibility
/// This eliminates type mismatches when result is assigned to PyValue variables
pub fn pow(base: anytype, exp: @TypeOf(base)) !PyValue {
    const T = @TypeOf(base);

    // Convert to f64 for complex-capable pow
    const base_f: f64 = switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(base),
        .float, .comptime_float => @floatCast(base),
        else => @compileError("pow requires numeric types"),
    };
    const exp_f: f64 = switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(exp),
        .float, .comptime_float => @floatCast(exp),
        else => @compileError("pow requires numeric types"),
    };

    // Use pyPowAsPyValue which returns PyValue directly for type compatibility
    return builtins.pyPowAsPyValue(base_f, exp_f);
}

const builtins = @import("../runtime/builtins.zig");

// ============================================================================
// Bitwise Operations
// ============================================================================

/// Bitwise and: a & b
pub fn and_(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a & b;
}

/// Bitwise or: a | b
pub fn or_(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a | b;
}

/// Bitwise xor: a ^ b
pub fn xor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a ^ b;
}

/// Bitwise inversion: ~a
pub fn invert(a: anytype) @TypeOf(a) {
    return ~a;
}

/// Left shift: a << b
pub fn lshift(a: anytype, b: anytype) @TypeOf(a) {
    const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
    return a << shift;
}

/// Right shift: a >> b
pub fn rshift(a: anytype, b: anytype) @TypeOf(a) {
    const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
    return a >> shift;
}

// ============================================================================
// Sequence Operations
// ============================================================================

/// Concatenation: a + b (for sequences)
/// Returns a new slice containing elements from both a and b
/// Caller must free the returned slice using the provided allocator
pub fn concat(allocator: std.mem.Allocator, a: anytype, b: @TypeOf(a)) !@TypeOf(a) {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    if (info == .pointer and info.pointer.size == .slice) {
        // Slice concatenation - allocate new slice with combined length
        const ElemType = info.pointer.child;
        const result = try allocator.alloc(ElemType, a.len + b.len);
        @memcpy(result[0..a.len], a);
        @memcpy(result[a.len..], b);
        return result;
    } else {
        // For non-slices, just return a (no allocation possible)
        return a;
    }
}

/// Concatenation without allocation (in-place for ArrayList)
pub fn concatInPlace(list: anytype, items: anytype) !void {
    try list.appendSlice(items);
}

/// Check containment: b in a
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn contains(sequence: anytype, item: anytype) bool {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return containsPyValue(sequence, item);
    }

    // Fast path: string slice containment
    if (SeqT == []const u8 and ItemT == []const u8) {
        return std.mem.indexOf(u8, sequence, item) != null;
    }

    // Standard iteration for same types
    for (sequence) |elem| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) return true;
        }
    }
    return false;
}

/// PyValue containment - compiles ONCE
fn containsPyValue(sequence: []const PyValue, item: PyValue) bool {
    const equality = @import("../runtime/equality.zig");
    for (sequence) |elem| {
        if (equality.pyValueEql(elem, item)) return true;
    }
    return false;
}

/// Count occurrences
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn countOf(sequence: anytype, item: anytype) usize {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return countOfPyValue(sequence, item);
    }

    // Standard iteration for same types
    var count: usize = 0;
    for (sequence) |elem| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) count += 1;
        }
    }
    return count;
}

/// PyValue count - compiles ONCE
fn countOfPyValue(sequence: []const PyValue, item: PyValue) usize {
    const equality = @import("../runtime/equality.zig");
    var count: usize = 0;
    for (sequence) |elem| {
        if (equality.pyValueEql(elem, item)) count += 1;
    }
    return count;
}

/// Index of first occurrence
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn indexOf(sequence: anytype, item: anytype) !usize {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return indexOfPyValue(sequence, item);
    }

    // Standard iteration for same types
    for (sequence, 0..) |elem, i| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) return i;
        }
    }
    return error.ValueError;
}

/// PyValue indexOf - compiles ONCE
fn indexOfPyValue(sequence: []const PyValue, item: PyValue) !usize {
    const equality = @import("../runtime/equality.zig");
    for (sequence, 0..) |elem, i| {
        if (equality.pyValueEql(elem, item)) return i;
    }
    return error.ValueError;
}

/// Get item at index: a[b]
pub fn getitem(sequence: anytype, idx: usize) @typeInfo(@TypeOf(sequence)).pointer.child {
    return sequence[idx];
}

/// Get length: len(a)
pub fn length(sequence: anytype) usize {
    return sequence.len;
}

// ============================================================================
// Attribute/Item Access
// ============================================================================

/// Attribute getter - creates a function that gets an attribute
pub fn attrgetter(comptime field: []const u8) fn (anytype) @TypeOf(@field(@as(@TypeOf(undefined), undefined), field)) {
    return struct {
        pub fn get(obj: anytype) @TypeOf(@field(obj, field)) {
            return @field(obj, field);
        }
    }.get;
}

/// Item getter - creates a function that gets an item at index
pub fn itemgetter(comptime idx: usize) fn (anytype) @typeInfo(@TypeOf(undefined)).pointer.child {
    return struct {
        pub fn get(seq: anytype) @typeInfo(@TypeOf(seq)).pointer.child {
            return seq[idx];
        }
    }.get;
}

// ============================================================================
// In-place Operations (for mutable values)
// ============================================================================

/// In-place addition: a += b
pub fn iadd(comptime T: type, a: *T, b: T) void {
    a.* += b;
}

/// In-place subtraction: a -= b
pub fn isub(comptime T: type, a: *T, b: T) void {
    a.* -= b;
}

/// In-place multiplication: a *= b
pub fn imul(comptime T: type, a: *T, b: T) void {
    a.* *= b;
}

/// In-place floor division: a //= b
pub fn ifloordiv(comptime T: type, a: *T, b: T) void {
    a.* = @divFloor(a.*, b);
}

/// In-place modulo: a %= b
pub fn imod(comptime T: type, a: *T, b: T) void {
    a.* = @mod(a.*, b);
}

/// In-place and: a &= b
pub fn iand(comptime T: type, a: *T, b: T) void {
    a.* &= b;
}

/// In-place or: a |= b
pub fn ior(comptime T: type, a: *T, b: T) void {
    a.* |= b;
}

/// In-place xor: a ^= b
pub fn ixor(comptime T: type, a: *T, b: T) void {
    a.* ^= b;
}

/// In-place left shift: a <<= b
pub fn ilshift(comptime T: type, comptime S: type, a: *T, b: S) void {
    const shift: std.math.Log2Int(T) = @intCast(b);
    a.* <<= shift;
}

/// In-place right shift: a >>= b
pub fn irshift(comptime T: type, comptime S: type, a: *T, b: S) void {
    const shift: std.math.Log2Int(T) = @intCast(b);
    a.* >>= shift;
}

// ============================================================================
// Special Operations
// ============================================================================

/// Check if object is callable
pub fn is_callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);
    return info == .@"fn" or info == .pointer and @typeInfo(info.pointer.child) == .@"fn";
}

/// Check if a is b (identity)
pub fn is_(a: anytype, b: @TypeOf(a)) bool {
    return &a == &b;
}

/// Check if a is not b
pub fn is_not(a: anytype, b: @TypeOf(a)) bool {
    return &a != &b;
}

// ============================================================================
// Index Operation (for Integral ABC)
// ============================================================================

/// operator.index(x) - Returns x.__index__() for objects that implement __index__
/// This is used to get an integer representation for use in slicing and other contexts
/// that require an integer. Raises TypeError if __index__ is not defined.
///
/// For built-in integers, returns the value directly.
/// For class instances with __index__, calls that method.
pub fn index(obj: anytype) PythonError!i64 {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);

    // Built-in integer types directly return the value
    if (type_predicates.isIntInfo(info)) {
        return @as(i64, @intCast(obj));
    }

    // For booleans, True = 1, False = 0
    if (T == bool) {
        return if (obj) 1 else 0;
    }

    // For pointers to structs, check for __index__ method
    if (info == .pointer and info.pointer.size == .one) {
        const ChildType = info.pointer.child;
        if (@typeInfo(ChildType) == .@"struct") {
            if (@hasDecl(ChildType, "__index__")) {
                // Call __index__() method - it may return error union
                const result = obj.__index__();
                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    return result catch return PythonError.TypeError;
                }
                return @as(i64, @intCast(result));
            }
        }
    }

    // For struct values (not pointers), check for __index__ method
    if (info == .@"struct") {
        if (@hasDecl(T, "__index__")) {
            const result = obj.__index__();
            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch return PythonError.TypeError;
            }
            return @as(i64, @intCast(result));
        }
    }

    // No __index__ method found - raise TypeError
    return PythonError.TypeError;
}

// ============================================================================
// Tests
// ============================================================================

test "comparison operators" {
    try std.testing.expect(lt(@as(i32, 1), @as(i32, 2)));
    try std.testing.expect(!lt(@as(i32, 2), @as(i32, 1)));
    try std.testing.expect(le(@as(i32, 1), @as(i32, 1)));
    try std.testing.expect(eq(@as(i32, 5), @as(i32, 5)));
    try std.testing.expect(ne(@as(i32, 5), @as(i32, 6)));
    try std.testing.expect(ge(@as(i32, 5), @as(i32, 5)));
    try std.testing.expect(gt(@as(i32, 6), @as(i32, 5)));
}

test "arithmetic operators" {
    try std.testing.expectEqual(@as(i32, 5), abs(@as(i32, -5)));
    try std.testing.expectEqual(@as(i32, 5), abs(@as(i32, 5)));
    try std.testing.expectEqual(@as(i32, 7), add(@as(i32, 3), @as(i32, 4)));
    try std.testing.expectEqual(@as(i32, 2), sub(@as(i32, 5), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 12), mul(@as(i32, 3), @as(i32, 4)));
    try std.testing.expectEqual(@as(i32, 3), floordiv(@as(i32, 10), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 1), mod(@as(i32, 10), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, -5), neg(@as(i32, 5)));
}

test "bitwise operators" {
    try std.testing.expectEqual(@as(u8, 0b1010 & 0b1100), and_(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b1010 | 0b1100), or_(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b1010 ^ 0b1100), xor(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b100), lshift(@as(u8, 1), @as(u8, 2)));
    try std.testing.expectEqual(@as(u8, 0b10), rshift(@as(u8, 8), @as(u8, 2)));
}

test "sequence operators" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expect(contains(&arr, @as(i32, 3)));
    try std.testing.expect(!contains(&arr, @as(i32, 6)));
    try std.testing.expectEqual(@as(usize, 1), countOf(&arr, @as(i32, 3)));
    try std.testing.expectEqual(@as(usize, 2), try indexOf(&arr, @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 3), getitem(&arr, 2));
    try std.testing.expectEqual(@as(usize, 5), length(&arr));
}

test "truth and not" {
    try std.testing.expect(truth(true));
    try std.testing.expect(!truth(false));
    try std.testing.expect(truth(@as(i32, 1)));
    try std.testing.expect(!truth(@as(i32, 0)));
    try std.testing.expect(not_(false));
    try std.testing.expect(!not_(true));
}

test "power" {
    // pow now returns PyValue (float or complex) for O(1) type compatibility
    const r1 = try pow(@as(i64, 2), @as(i64, 3));
    try std.testing.expect(r1 == .float and r1.float == 8.0);

    const r2 = try pow(@as(i64, 5), @as(i64, 0));
    try std.testing.expect(r2 == .float and r2.float == 1.0);

    const r3 = try pow(@as(i64, 3), @as(i64, 3));
    try std.testing.expect(r3 == .float and r3.float == 27.0);

    // Complex result for negative base with non-integer exponent
    const r4 = try pow(@as(f64, -2.0), @as(f64, 0.5));
    try std.testing.expect(r4 == .complex);
}

test "in-place operations" {
    var x: i32 = 5;
    iadd(&x, 3);
    try std.testing.expectEqual(@as(i32, 8), x);

    isub(&x, 2);
    try std.testing.expectEqual(@as(i32, 6), x);

    imul(&x, 2);
    try std.testing.expectEqual(@as(i32, 12), x);
}

test "index operation" {
    // Built-in integers
    try std.testing.expectEqual(@as(i64, 42), try index(@as(i32, 42)));
    try std.testing.expectEqual(@as(i64, -10), try index(@as(i64, -10)));

    // Booleans
    try std.testing.expectEqual(@as(i64, 1), try index(true));
    try std.testing.expectEqual(@as(i64, 0), try index(false));
}
