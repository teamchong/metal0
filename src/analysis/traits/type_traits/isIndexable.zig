//! isIndexable - Check if type supports obj[key]
//! USE: Before emitting subscript expressions
//! RETURNS: true for list, tuple, array, dict, string, bytes

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");

pub fn isIndexable(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array or tag == .dict or string_traits.isStringLike(t);
}
