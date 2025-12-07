//! getElementType - Get element type of container
//! USE: When inferring iteration variable type
//! RETURNS: element type for list/set/array, unknown for tuple

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn getElementType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .set => t.set.*,
        .tuple => .unknown,
        .array => t.array.element_type.*,
        .frozenset => t.frozenset.*,
        else => .unknown,
    };
}
