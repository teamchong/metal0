//! isFloatType - Check if type is float (for operator semantics)
//! USE: Internal helper for operator traits
//! RETURNS: true for float, complex

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isFloatType(t: NativeType) bool {
    return t == .float or t == .complex;
}
