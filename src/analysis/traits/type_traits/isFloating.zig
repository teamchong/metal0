//! isFloating - Check if type is floating-point
//! USE: Before emitting %, // (Python float semantics differ from Zig)
//! RETURNS: true for float, complex

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isFloating(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .float or tag == .complex;
}
