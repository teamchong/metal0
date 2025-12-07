//! isTuple - Check if type is a tuple
//! USE: For immutable sequence handling, unpacking
//! RETURNS: true for tuple

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isTuple(t: NativeType) bool {
    return t == .tuple;
}
