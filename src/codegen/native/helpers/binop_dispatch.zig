/// Binary Operator Dispatch Helper
///
/// Centralizes special binary operator handling (Mod, Pow, FloorDiv)
/// that requires runtime calls instead of Zig operators.
///
/// Usage:
///   if (getSpecialBinOpCall(bin.op)) |call| {
///       try self.emit(call.prefix);
///       try emitLeft();
///       try self.emit(", ");
///       try emitRight();
///       try self.emit(call.suffix);
///   } else {
///       // standard binop handling
///   }
///
const std = @import("std");
const ast = @import("analysis.ast");

/// Special binary operator call info
pub const SpecialBinOpCall = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Get special binary operator call info if op needs runtime handling.
/// Returns null for operators that can use standard Zig operators.
///
/// Handles:
/// - Mod: runtime.OperatorMod{}.call(left, right) - Python's floored modulo
/// - Pow: std.math.pow(i64, left, right) - Integer power
/// - FloorDiv: runtime.OperatorFloordiv{}.call(left, right) - Python's floor division
pub fn getSpecialBinOpCall(op: ast.Operator) ?SpecialBinOpCall {
    return switch (op) {
        .Mod => .{ .prefix = "runtime.OperatorMod{}.call(", .suffix = ")" },
        .Pow => .{ .prefix = "std.math.pow(i64, ", .suffix = ")" },
        .FloorDiv => .{ .prefix = "runtime.OperatorFloordiv{}.call(", .suffix = ")" },
        else => null,
    };
}

/// Check if operator is a special operator (Mod, Pow, FloorDiv)
pub fn isSpecialBinOp(op: ast.Operator) bool {
    return getSpecialBinOpCall(op) != null;
}
