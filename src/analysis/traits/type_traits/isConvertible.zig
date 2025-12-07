//! isConvertible - Check if type A can implicitly convert to type B
//! USE: When checking function argument compatibility
//! CONVERSIONS: int->float, int->bigint, bool->int

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const isUnknown = @import("isUnknown.zig").isUnknown;

pub fn isConvertible(from: NativeType, to: NativeType) bool {
    if (from == to) return true;
    if (isUnknown(from) or isUnknown(to)) return true;
    const from_tag = @as(std.meta.Tag(@TypeOf(from)), from);
    const to_tag = @as(std.meta.Tag(@TypeOf(to)), to);
    if (from_tag == .int and to_tag == .float) return true;
    if (from_tag == .int and to_tag == .bigint) return true;
    if (from_tag == .bool and to_tag == .int) return true;
    return false;
}
