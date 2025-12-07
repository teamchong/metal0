//! getIteratorElementType - Get element type when iterating
//! USE: When inferring "for x in container" variable type
//! NOTE: Dict iteration yields keys, not (key, value) pairs

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn getIteratorElementType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .set => t.set.*,
        .tuple => .unknown,
        .array => t.array.element_type.*,
        .dict => t.dict.key.*,
        .frozenset => t.frozenset.*,
        else => .unknown,
    };
}
