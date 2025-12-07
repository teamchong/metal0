//! supportsConcat - Check if container + container is valid
//! USE: Before emitting list + list or tuple + tuple
//! RETURNS: true for list, tuple

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn supportsConcat(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple;
}
