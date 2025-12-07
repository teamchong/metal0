//! hasUnknownOperand - Check if either operand needs runtime dispatch
//! USE: When deciding if runtime PyObject dispatch needed
//! RETURNS: true if left or right is unknown

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn hasUnknownOperand(left: NativeType, right: NativeType) bool {
    return left == .unknown or right == .unknown;
}
