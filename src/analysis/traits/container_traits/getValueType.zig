//! getValueType - Get value type of mapping
//! USE: When inferring dict[key] result type
//! RETURNS: value type for dict, unknown otherwise

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn getValueType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .dict => t.dict.value.*,
        else => .unknown,
    };
}
