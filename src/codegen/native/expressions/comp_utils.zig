//! Comprehension utilities - shared helpers and type maps
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

/// Set of builtins that return int (for type inference)
pub const IntReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "len", {} },
    .{ "ord", {} },
    .{ "int", {} },
    .{ "abs", {} },
    .{ "hash", {} },
    .{ "id", {} },
});

/// Set of builtins that return bool (for type inference)
pub const BoolReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "all", {} },
    .{ "any", {} },
    .{ "callable", {} },
    .{ "hasattr", {} },
    .{ "isinstance", {} },
    .{ "issubclass", {} },
    .{ "bool", {} },
});

/// String methods that return a string type
pub const StringReturningMethods = std.StaticStringMap(void).initComptime(.{
    .{ "replace", {} },
    .{ "strip", {} },
    .{ "lstrip", {} },
    .{ "rstrip", {} },
    .{ "lower", {} },
    .{ "upper", {} },
    .{ "capitalize", {} },
    .{ "title", {} },
    .{ "swapcase", {} },
    .{ "casefold", {} },
    .{ "center", {} },
    .{ "ljust", {} },
    .{ "rjust", {} },
    .{ "zfill", {} },
    .{ "join", {} },
    .{ "format", {} },
    .{ "expandtabs", {} },
    .{ "encode", {} },
    .{ "decode", {} },
    .{ "translate", {} },
});

/// Check if an expression evaluates to an integer type
pub fn isIntExpr(node: ast.Node) bool {
    return switch (node) {
        .binop => true, // Arithmetic operations yield int
        .constant => |c| c.value == .int,
        .name => true, // Assume loop vars from range() are int (could be smarter)
        .call => |c| {
            if (c.func.* == .name) return IntReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Check if an expression evaluates to a boolean type
pub fn isBoolExpr(node: ast.Node) bool {
    return switch (node) {
        .compare => true, // Comparisons (including 'in') yield bool
        .boolop => true, // and/or yield bool
        .unaryop => |u| u.op == .Not, // not yields bool
        .constant => |c| type_traits.isBoolean(if (c.value == .bool) .bool else .unknown),
        .call => |c| {
            if (c.func.* == .name) return BoolReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Get the Zig element type string for a generator expression element
pub fn getGenExpElementType(elt: ast.Node) []const u8 {
    // Check for f-string first - common in generator expressions
    if (elt == .fstring) return "[]u8";
    // Check for string constant
    if (elt == .constant and elt.constant.value == .string) return "[]const u8";
    if (isBoolExpr(elt)) return "bool";
    if (isIntExpr(elt)) return "i64";
    // Default to i64 for unknown types
    return "i64";
}

/// Check if method name returns a string type
pub fn isStringReturningMethod(method_name: []const u8) bool {
    return StringReturningMethods.has(method_name);
}

/// Convert NativeType to Zig type string for dict comprehension value types
pub fn nativeTypeToZigStr(native_type: NativeType) []const u8 {
    return switch (native_type) {
        .int => "i64",
        .bigint, .unified_int => "*runtime.bigint.BigInt",
        .usize => "usize",
        .float => "f64",
        .bool => "bool",
        .string => "[]const u8",
        .bytes => "runtime.builtins.PyBytes",
        .complex => "runtime.complex.PyComplex",
        .none => "?void",
        // All other types fall back to PyValue for heterogeneous dicts
        else => "runtime.PyValue",
    };
}
