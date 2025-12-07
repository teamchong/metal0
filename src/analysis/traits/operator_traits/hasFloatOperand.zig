//! hasFloatOperand - Check if either operand is float
//! USE: When deciding %, //, ** semantics
//! RETURNS: true if left or right is float/complex

const NativeType = @import("../../native_types/core.zig").NativeType;
const isFloatType = @import("isFloatType.zig").isFloatType;

pub fn hasFloatOperand(left: NativeType, right: NativeType) bool {
    return isFloatType(left) or isFloatType(right);
}
