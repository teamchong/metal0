//! getModuloSemantics - Get semantics for % operator
//! USE: Before emitting modulo - Python floored vs Zig truncated
//! RETURNS: .zig_native (int), .python_floored (float), .runtime_dispatch (unknown)

const NativeType = @import("../../native_types/core.zig").NativeType;
const isFloatType = @import("isFloatType.zig").isFloatType;
const hasUnknownOperand = @import("hasUnknownOperand.zig").hasUnknownOperand;

pub const OperatorSemantics = enum { zig_native, python_floored, runtime_dispatch };

pub fn getModuloSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    if (isFloatType(left) or isFloatType(right)) return .python_floored;
    return .zig_native;
}
