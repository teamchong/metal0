//! isImmutableContainer - Check if container cannot be modified
//! USE: For tuple, frozenset handling
//! RETURNS: true for tuple, frozenset

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isImmutableContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .tuple or tag == .frozenset;
}
