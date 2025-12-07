//! isContainer - Check if type is a container (has elements)
//! USE: Before emitting len(), iteration, or membership tests
//! RETURNS: true for list, dict, set, tuple, array

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .set or tag == .tuple or tag == .array;
}
