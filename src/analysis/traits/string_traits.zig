/// String/Bytes Traits - Unified helpers for string and bytes type decisions
///
/// Similar to function_traits.zig, this provides unified helpers for:
/// | Pattern                    | Solution                                      |
/// |----------------------------|-----------------------------------------------|
/// | Type checking              | isStringLike, isBytes, isString              |
/// | Repr selection             | getReprFn, getReprPrefix                     |
/// | Encoding operations        | supportsEncode, supportsDecode               |
/// | Concatenation              | canConcat, getConcatResultType               |
/// | Multiplication             | canRepeat, getRepeatResultType               |
///
/// USAGE:
/// ```zig
/// const traits = @import("string_traits.zig");
///
/// // Type checking
/// if (traits.isStringLike(t)) { /* handle string or bytes */ }
/// if (traits.isBytes(t)) { /* bytes-specific handling */ }
///
/// // Repr selection
/// const repr_fn = traits.getReprFn(t); // "bytesRepr" or "stringRepr"
/// const prefix = traits.getReprPrefix(t); // "b'" or "'"
///
/// // Operation validity
/// if (traits.canConcat(left, right)) { /* use std.mem.concat */ }
/// ```

const std = @import("std");
const NativeType = @import("../native_types/core.zig").NativeType;

// ============================================================================
// TYPE CHECKING - Unified predicates
// ============================================================================

/// Check if type is string-like (string or bytes)
/// Use this for operations that work on both (e.g., concatenation, len)
pub fn isStringLike(t: NativeType) bool {
    return t == .string or t == .bytes;
}

/// Check if type is specifically bytes
/// Use this when bytes-specific behavior is needed (e.g., b'...' repr)
pub fn isBytes(t: NativeType) bool {
    return t == .bytes;
}

/// Check if type is specifically string (not bytes)
pub fn isString(t: NativeType) bool {
    return t == .string;
}

/// Check if either type is string-like
pub fn hasStringLikeOperand(left: NativeType, right: NativeType) bool {
    return isStringLike(left) or isStringLike(right);
}

/// Check if both types are string-like
pub fn bothStringLike(left: NativeType, right: NativeType) bool {
    return isStringLike(left) and isStringLike(right);
}

// ============================================================================
// REPR SELECTION - Choose correct repr function/format
// ============================================================================

/// Get the runtime repr function name for a type
/// Returns "bytesRepr" for bytes, "stringRepr" otherwise
pub fn getReprFn(t: NativeType) []const u8 {
    return if (isBytes(t)) "bytesRepr" else "stringRepr";
}

/// Get the full runtime repr function path
pub fn getReprFnPath(t: NativeType) []const u8 {
    return if (isBytes(t)) "runtime.builtins.bytesRepr" else "runtime.builtins.pyRepr";
}

/// Get the repr prefix for a type ("b'" for bytes, "'" for string)
pub fn getReprPrefix(t: NativeType) []const u8 {
    return if (isBytes(t)) "b'" else "'";
}

/// Get the print format for a type
pub fn getPrintFormat(t: NativeType) []const u8 {
    return if (isStringLike(t)) "{s}" else "{any}";
}

// ============================================================================
// OPERATION VALIDITY - Check if operations are valid
// ============================================================================

/// Check if two types can be concatenated with +
/// Valid: str + str, bytes + bytes
/// Invalid: str + bytes (Python raises TypeError)
pub fn canConcat(left: NativeType, right: NativeType) bool {
    if (isString(left) and isString(right)) return true;
    if (isBytes(left) and isBytes(right)) return true;
    return false;
}

/// Check if type can be repeated with * int
pub fn canRepeat(t: NativeType) bool {
    return isStringLike(t);
}

/// Get the result type of concatenation
/// Returns null if concatenation is invalid
pub fn getConcatResultType(left: NativeType, right: NativeType) ?NativeType {
    if (isString(left) and isString(right)) return .{ .string = .runtime };
    if (isBytes(left) and isBytes(right)) return .bytes;
    return null;
}

/// Get the result type of string/bytes repetition
pub fn getRepeatResultType(t: NativeType) ?NativeType {
    if (isString(t)) return .{ .string = .runtime };
    if (isBytes(t)) return .bytes;
    return null;
}

// ============================================================================
// ENCODING OPERATIONS - Check encoding/decoding validity
// ============================================================================

/// Check if type supports .encode() method
/// Only strings support encode (str -> bytes)
pub fn supportsEncode(t: NativeType) bool {
    return isString(t);
}

/// Check if type supports .decode() method
/// Only bytes support decode (bytes -> str)
pub fn supportsDecode(t: NativeType) bool {
    return isBytes(t);
}

// ============================================================================
// ZIG TYPE MAPPING - Convert to Zig types
// ============================================================================

/// Get the Zig type for a string-like type
/// Both string and bytes map to []const u8 in Zig
pub fn toZigType(t: NativeType) []const u8 {
    if (isStringLike(t)) return "[]const u8";
    return "[]const u8"; // Default fallback
}

/// Get the element type for iteration
/// Both string and bytes iterate over u8
pub fn getElementType(t: NativeType) []const u8 {
    if (isStringLike(t)) return "u8";
    return "u8";
}

// ============================================================================
// TESTS
// ============================================================================

test "isStringLike" {
    try std.testing.expect(isStringLike(.{ .string = .literal }));
    try std.testing.expect(isStringLike(.{ .string = .runtime }));
    try std.testing.expect(isStringLike(.bytes));
    try std.testing.expect(!isStringLike(.int));
    try std.testing.expect(!isStringLike(.float));
}

test "getReprFn" {
    try std.testing.expectEqualStrings("bytesRepr", getReprFn(.bytes));
    try std.testing.expectEqualStrings("stringRepr", getReprFn(.{ .string = .literal }));
}

test "canConcat" {
    try std.testing.expect(canConcat(.{ .string = .literal }, .{ .string = .runtime }));
    try std.testing.expect(canConcat(.bytes, .bytes));
    try std.testing.expect(!canConcat(.{ .string = .literal }, .bytes));
    try std.testing.expect(!canConcat(.bytes, .{ .string = .literal }));
}
