//! getIndexResultType - Get type of obj[i] expression
//! USE: When inferring type of subscript expressions
//! RETURNS: element type for containers, char for string, byte for bytes

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn getIndexResultType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .tuple => .unknown,
        .array => t.array.element_type.*,
        .dict => t.dict.value.*,
        .string => .{ .string = .literal },
        .bytes => .{ .int = .bounded },
        else => .unknown,
    };
}
