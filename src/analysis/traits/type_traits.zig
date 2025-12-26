/// Type Traits - Unified helpers for type arithmetic and conversion decisions
///
/// Centralizes type-related decisions that were previously scattered across:
/// - expressions.zig (binary operation type inference)
/// - arithmetic.zig (operator codegen)
/// - core.zig (type conversion)
///
/// | Pattern                    | Solution                                      |
/// |----------------------------|-----------------------------------------------|
/// | Numeric checking           | isNumeric, isIntegral, isFloating            |
/// | Container checking         | isContainer, isSequence, isMapping           |
/// | Type compatibility         | areComparable, isConvertible                 |
/// | Binary operations          | binaryResultType, needsPromotion             |
/// | Indexing                   | isIndexable, getIndexResultType              |
///
/// USAGE:
/// ```zig
/// const traits = @import("type_traits.zig");
///
/// // Type checking
/// if (traits.isNumeric(t)) { /* can do arithmetic */ }
/// if (traits.isIndexable(t)) { /* can use [] */ }
///
/// // Binary operations
/// const result_type = traits.binaryResultType(.Add, left, right);
/// if (traits.needsPromotion(left, right)) { /* convert to common type */ }
///
/// // Comparisons
/// if (traits.areComparable(a, b)) { /* can use == */ }
/// ```

const std = @import("std");
const NativeType = @import("../native_types/core.zig").NativeType;
const string_traits = @import("string_traits.zig");

// ============================================================================
// NUMERIC TYPE CHECKING
// ============================================================================

/// Check if type is numeric (int, float, bigint, complex)
pub fn isNumeric(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .int or tag == .float or tag == .bigint or tag == .complex or tag == .usize;
}

/// Check if type is integral (int, bigint, usize)
pub fn isIntegral(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .int or tag == .bigint or tag == .usize;
}

/// Check if type is floating point (float, complex)
pub fn isFloating(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .float or tag == .complex;
}

/// Check if type is boolean
pub fn isBoolean(t: NativeType) bool {
    return t == .bool;
}

/// Check if type is None
pub fn isNone(t: NativeType) bool {
    return t == .none;
}

/// Check if type is optional (?T) - can be compared to null
pub fn isOptional(t: NativeType) bool {
    return t == .optional;
}

/// Check if type is unknown/dynamic
pub fn isUnknown(t: NativeType) bool {
    return t == .unknown;
}

/// Check if type is a class instance (custom Python class)
pub fn isClassInstance(t: NativeType) bool {
    return t == .class_instance;
}

/// Check if type is callable (function, lambda, method)
pub fn isCallable(t: NativeType) bool {
    return t == .callable;
}

/// Check if type is a fixed-size array
pub fn isArray(t: NativeType) bool {
    return t == .array;
}

// ============================================================================
// CONTAINER TYPE CHECKING
// ============================================================================

/// Check if type is a container (list, dict, set, tuple)
pub fn isContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .set or tag == .tuple or tag == .array;
}

/// Check if type is a sequence (list, tuple, array, string, bytes)
pub fn isSequence(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array or string_traits.isStringLike(t);
}

/// Check if type is a mapping (dict)
pub fn isMapping(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .dict;
}

/// Check if type is iterable
pub fn isIterable(t: NativeType) bool {
    return isSequence(t) or isMapping(t) or t == .iterator or t == .generator;
}

// ============================================================================
// DICTIONARY KEY TYPE CLASSIFICATION
// ============================================================================

/// Dictionary key type classification for proper HashMap type selection
pub const DictKeyType = enum {
    int, // i64 keys -> std.AutoHashMap(i64, V)
    string, // []const u8 keys -> hashmap_helper.StringHashMap(V)
    pyvalue, // runtime.PyValue keys -> hashmap_helper.StringHashMap(PyValue)
};

/// Classify a NativeType for use as a dictionary key type
/// Used by dict.zig and comprehensions.zig to select the correct HashMap type
pub fn getDictKeyType(t: NativeType) DictKeyType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        // Integer types use AutoHashMap(i64, V)
        .int, .bigint, .unified_int, .usize => .int,
        // String types use StringHashMap(V) with []const u8 keys
        .string, .bytes => .string,
        // All other types (unknown, pyvalue, tuples, etc.) use StringHashMap(PyValue)
        // This handles mixed key types and runtime-determined keys
        else => .pyvalue,
    };
}

// ============================================================================
// INDEXING
// ============================================================================

/// Check if type supports indexing with []
pub fn isIndexable(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array or tag == .dict or string_traits.isStringLike(t);
}

/// Check if type supports slicing with [start:end]
pub fn isSliceable(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array or string_traits.isStringLike(t);
}

/// Get the result type of indexing (t[i])
pub fn getIndexResultType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .tuple => .unknown, // Tuple indexing can return different types
        .array => t.array.element_type.*,
        .dict => t.dict.value.*,
        .string => .{ .string = .literal }, // Single char
        .bytes => .{ .int = .bounded }, // Single byte as int
        else => .unknown,
    };
}

// ============================================================================
// TYPE COMPARISON AND COMPATIBILITY
// ============================================================================

/// Check if two types can be compared with ==, !=
pub fn areComparable(a: NativeType, b: NativeType) bool {
    // Unknown types are always comparable (runtime check)
    if (isUnknown(a) or isUnknown(b)) return true;

    // Same type category is comparable
    const a_tag = @as(std.meta.Tag(@TypeOf(a)), a);
    const b_tag = @as(std.meta.Tag(@TypeOf(b)), b);
    if (a_tag == b_tag) return true;

    // Numeric types are comparable
    if (isNumeric(a) and isNumeric(b)) return true;

    // String-like types are comparable
    if (string_traits.isStringLike(a) and string_traits.isStringLike(b)) return true;

    // None is comparable with anything (for is None checks)
    if (isNone(a) or isNone(b)) return true;

    return false;
}

/// Check if two types can be ordered with <, <=, >, >=
pub fn areOrderable(a: NativeType, b: NativeType) bool {
    // Unknown types are orderable (runtime check)
    if (isUnknown(a) or isUnknown(b)) return true;

    // Numeric types are orderable
    if (isNumeric(a) and isNumeric(b)) return true;

    // String-like types are orderable (lexicographic)
    if (string_traits.isStringLike(a) and string_traits.isStringLike(b)) return true;

    // Sequences of same type are orderable
    if (isSequence(a) and isSequence(b)) return true;

    return false;
}

/// Check if type A can be implicitly converted to type B
pub fn isConvertible(from: NativeType, to: NativeType) bool {
    if (from == to) return true;
    if (isUnknown(from) or isUnknown(to)) return true;

    const from_tag = @as(std.meta.Tag(@TypeOf(from)), from);
    const to_tag = @as(std.meta.Tag(@TypeOf(to)), to);

    // int -> float is always valid
    if (from_tag == .int and to_tag == .float) return true;

    // int -> bigint is always valid
    if (from_tag == .int and to_tag == .bigint) return true;

    // bool -> int is valid
    if (from_tag == .bool and to_tag == .int) return true;

    return false;
}

// ============================================================================
// BINARY OPERATION TYPE INFERENCE
// ============================================================================

/// Re-export from dedicated module for full functionality including hints
const binaryResultType_mod = @import("type_traits/binaryResultType.zig");

pub const BinOp = binaryResultType_mod.BinOp;
pub const OperationHints = binaryResultType_mod.OperationHints;
pub const binaryResultType = binaryResultType_mod.binaryResultType;
pub const binaryResultTypeWithHints = binaryResultType_mod.binaryResultTypeWithHints;

/// Check if promotion is needed for binary operation
pub fn needsPromotion(left: NativeType, right: NativeType) bool {
    if (!isNumeric(left) or !isNumeric(right)) return false;

    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    return left_tag != right_tag;
}

// ============================================================================
// TESTS
// ============================================================================

test "isNumeric" {
    try std.testing.expect(isNumeric(.{ .int = .bounded }));
    try std.testing.expect(isNumeric(.float));
    try std.testing.expect(isNumeric(.bigint));
    try std.testing.expect(!isNumeric(.{ .string = .literal }));
    try std.testing.expect(!isNumeric(.bytes));
}

test "isIndexable" {
    try std.testing.expect(isIndexable(.{ .string = .literal }));
    try std.testing.expect(isIndexable(.bytes));
    try std.testing.expect(!isIndexable(.{ .int = .bounded }));
    try std.testing.expect(!isIndexable(.float));
}

test "binaryResultType" {
    // int + int = int
    const int_int = binaryResultType(.Add, .{ .int = .bounded }, .{ .int = .bounded });
    try std.testing.expect(int_int == .int);

    // int + float = float
    const int_float = binaryResultType(.Add, .{ .int = .bounded }, .float);
    try std.testing.expect(int_float == .float);

    // int / int = float (true division)
    const div_result = binaryResultType(.Div, .{ .int = .bounded }, .{ .int = .bounded });
    try std.testing.expect(div_result == .float);
}
