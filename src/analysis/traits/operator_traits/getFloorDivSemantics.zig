//! getFloorDivSemantics - Get semantics for // operator
//! USE: Before emitting floor division - @divFloor vs @floor(a/b)
//! RETURNS: .zig_native (int), .python_floored (float), .runtime_dispatch (unknown)

const NativeType = @import("../../native_types/core.zig").NativeType;
const isFloatType = @import("isFloatType.zig").isFloatType;
const hasUnknownOperand = @import("hasUnknownOperand.zig").hasUnknownOperand;
pub const OperatorSemantics = @import("getModuloSemantics.zig").OperatorSemantics;

pub fn getFloorDivSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    if (isFloatType(left) or isFloatType(right)) return .python_floored;
    return .zig_native;
}
