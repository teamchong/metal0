//! isIntegral - Check if type is integer (for bitwise ops, array index)
//! USE: Before emitting &, |, ^, <<, >> or array[index]
//! RETURNS: true for int, bigint, usize

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isIntegral(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .int or tag == .bigint or tag == .usize;
}
