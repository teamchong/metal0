//! supportsSetItem - Check if container[key] = value is valid
//! USE: Before emitting subscript assignment
//! RETURNS: true for list, dict, array

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsSetItem(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .array;
}
