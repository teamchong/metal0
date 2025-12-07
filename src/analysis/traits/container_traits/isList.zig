//! isList - Check if type is a list
//! USE: Before emitting .append(), .extend(), list-specific ops
//! RETURNS: true for list

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isList(t: NativeType) bool {
    return t == .list;
}
