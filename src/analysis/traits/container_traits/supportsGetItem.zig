//! supportsGetItem - Check if container[key] is valid
//! USE: Before emitting subscript access
//! RETURNS: true for list, dict, tuple, array

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsGetItem(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .tuple or tag == .array;
}
