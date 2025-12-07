//! isNone - Check if type is None
//! USE: When checking "x is None" comparisons
//! RETURNS: true for .none type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isNone(t: NativeType) bool {
    return t == .none;
}
