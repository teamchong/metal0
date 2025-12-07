//! isMutableContainer - Check if container can be modified
//! USE: Before emitting mutation operations
//! RETURNS: true for list, dict, set

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isMutableContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .set;
}
