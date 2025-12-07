//! areComparable - Check if two types can use ==, !=
//! USE: Before emitting equality comparisons
//! RETURNS: true for same types, numerics, strings, or None with anything

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");
const isNumeric = @import("isNumeric.zig").isNumeric;
const isUnknown = @import("isUnknown.zig").isUnknown;
const isNone = @import("isNone.zig").isNone;

pub fn areComparable(a: NativeType, b: NativeType) bool {
    if (isUnknown(a) or isUnknown(b)) return true;
    const a_tag = @as(std.meta.Tag(@TypeOf(a)), a);
    const b_tag = @as(std.meta.Tag(@TypeOf(b)), b);
    if (a_tag == b_tag) return true;
    if (isNumeric(a) and isNumeric(b)) return true;
    if (string_traits.isStringLike(a) and string_traits.isStringLike(b)) return true;
    if (isNone(a) or isNone(b)) return true;
    return false;
}
