//! isNumeric - Check if type supports arithmetic (+, -, *, /)
//! USE: Before emitting arithmetic operations
//! RETURNS: true for int, float, bigint, unified_int, complex, usize

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isNumeric(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .int or tag == .float or tag == .bigint or tag == .unified_int or tag == .complex or tag == .usize;
}
