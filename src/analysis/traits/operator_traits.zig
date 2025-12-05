/// Operator traits for Python-compatible semantics
///
/// Python and Zig have different semantics for certain operators on floats:
/// | Operator | Python Semantics              | Zig Semantics           |
/// |----------|-------------------------------|-------------------------|
/// | %        | Floored modulo: a-floor(a/b)*b | Truncated: @mod        |
/// | //       | Floor division                | @divFloor (int only)   |
/// | **       | Can return complex            | std.math.pow           |
///
/// This module provides traits that codegen can query to emit correct code.
/// One source of truth, used by:
/// - arithmetic.zig (main binop codegen)
/// - async_state_machine.zig (async state machine binops)
/// - methods/float.zig (float dunder methods)

const std = @import("std");
const NativeType = @import("../native_types/core.zig").NativeType;

/// Operator semantic variants
pub const OperatorSemantics = enum {
    /// Zig's native operator works correctly for Python semantics
    zig_native,
    /// Need Python's floored version (sign follows divisor)
    python_floored,
    /// Need runtime dispatch (unknown types)
    runtime_dispatch,
};

/// Check if type is a float type (f64, comptime_float, etc.)
pub fn isFloatType(t: NativeType) bool {
    return t == .float or t == .complex;
}

/// Check if either operand is a float type
pub fn hasFloatOperand(left: NativeType, right: NativeType) bool {
    return isFloatType(left) or isFloatType(right);
}

/// Check if either operand has unknown type (needs runtime dispatch)
pub fn hasUnknownOperand(left: NativeType, right: NativeType) bool {
    return left == .unknown or right == .unknown;
}

/// Get modulo operator semantics based on operand types
/// Python's % uses floored division for floats: a - floor(a/b) * b
/// Zig's @mod uses truncated division
pub fn getModuloSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    if (hasFloatOperand(left, right)) return .python_floored;
    return .zig_native;
}

/// Get floor division semantics based on operand types
/// Python's // returns float for float operands: floor(a/b)
/// Zig's @divFloor only works for integers
pub fn getFloorDivSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    if (hasFloatOperand(left, right)) return .python_floored;
    return .zig_native;
}

/// Get power operator semantics
/// Python's ** can return complex for negative base with fractional exponent
pub fn getPowerSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    // Power always needs special handling for proper Python semantics
    return .python_floored;
}

// ============================================================================
// Code Generation Helpers
// These emit the correct Zig code based on operator semantics
// ============================================================================

/// Emit Python-compatible modulo code
/// For floats: runtime.pyFloatMod(a, b)
/// For ints: @mod(a, b)
/// For unknown: runtime.pyMod(allocator, a, b)
pub fn emitModulo(
    writer: anytype,
    left: NativeType,
    right: NativeType,
) !void {
    const semantics = getModuloSemantics(left, right);
    switch (semantics) {
        .python_floored => try writer.writeAll("runtime.pyFloatMod("),
        .runtime_dispatch => try writer.writeAll("runtime.pyMod(__global_allocator, "),
        .zig_native => try writer.writeAll("@mod("),
    }
}

/// Emit Python-compatible floor division code
/// For floats: @floor(a / b)
/// For ints: @divFloor(a, b)
pub fn emitFloorDiv(
    writer: anytype,
    left: NativeType,
    right: NativeType,
) !void {
    const semantics = getFloorDivSemantics(left, right);
    switch (semantics) {
        .python_floored => try writer.writeAll("@floor(("),
        .runtime_dispatch => try writer.writeAll("runtime.pyFloorDiv("),
        .zig_native => try writer.writeAll("@divFloor("),
    }
}

/// Get the closing for floor division (different for floats vs ints)
pub fn getFloorDivClose(left: NativeType, right: NativeType) []const u8 {
    const semantics = getFloorDivSemantics(left, right);
    return switch (semantics) {
        .python_floored => ") / (", // Need to close with ") / (" and then ")" after right operand
        .runtime_dispatch => ", ",
        .zig_native => ", ",
    };
}

/// Check if floor div needs special float handling
pub fn needsFloatFloorDiv(left: NativeType, right: NativeType) bool {
    return getFloorDivSemantics(left, right) == .python_floored;
}

/// Check if modulo needs float handling
pub fn needsFloatModulo(left: NativeType, right: NativeType) bool {
    return getModuloSemantics(left, right) == .python_floored;
}

/// Check if modulo needs runtime dispatch
pub fn needsRuntimeModulo(left: NativeType, right: NativeType) bool {
    return getModuloSemantics(left, right) == .runtime_dispatch;
}
