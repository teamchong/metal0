//! getPowerSemantics - Get semantics for ** operator
//! USE: Before emitting power - Python can return complex for neg base
//! RETURNS: .python_floored (always needs special handling)

const NativeType = @import("../../native_types/core.zig").NativeType;
const hasUnknownOperand = @import("hasUnknownOperand.zig").hasUnknownOperand;
pub const OperatorSemantics = @import("getModuloSemantics.zig").OperatorSemantics;

pub fn getPowerSemantics(left: NativeType, right: NativeType) OperatorSemantics {
    if (hasUnknownOperand(left, right)) return .runtime_dispatch;
    return .python_floored;
}
