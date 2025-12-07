//! isSet - Check if type is a set
//! USE: Before emitting .add(), .remove(), set operations
//! RETURNS: true for set

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isSet(t: NativeType) bool {
    return t == .set;
}
