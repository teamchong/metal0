//! isSequence - Check if type is ordered and indexable
//! USE: Before emitting sorted(), reversed(), or index-based access
//! RETURNS: true for list, tuple, array, string, bytes

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");

pub fn isSequence(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array or string_traits.isStringLike(t);
}
