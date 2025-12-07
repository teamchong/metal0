//! supportsRepeat - Check if container * int is valid
//! USE: Before emitting [1,2] * 3
//! RETURNS: true for list, tuple

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsRepeat(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple;
}
