//! supportsPush - Check if container supports .append()
//! USE: Before emitting list.append(x)
//! RETURNS: true for list

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsPush(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list;
}
