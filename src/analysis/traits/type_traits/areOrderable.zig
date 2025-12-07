//! areOrderable - Check if two types can use <, <=, >, >=
//! USE: Before emitting ordering comparisons or sorted()
//! RETURNS: true for numerics, strings, or sequences

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");
const isNumeric = @import("isNumeric.zig").isNumeric;
const isSequence = @import("isSequence.zig").isSequence;
const isUnknown = @import("isUnknown.zig").isUnknown;

pub fn areOrderable(a: NativeType, b: NativeType) bool {
    if (isUnknown(a) or isUnknown(b)) return true;
    if (isNumeric(a) and isNumeric(b)) return true;
    if (string_traits.isStringLike(a) and string_traits.isStringLike(b)) return true;
    if (isSequence(a) and isSequence(b)) return true;
    return false;
}
