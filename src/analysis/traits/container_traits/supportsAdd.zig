//! supportsAdd - Check if container supports .add()
//! USE: Before emitting set.add(x)
//! RETURNS: true for set

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsAdd(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .set;
}
