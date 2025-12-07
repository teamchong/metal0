//! getKeyType - Get key type of mapping
//! USE: When inferring dict iteration key type
//! RETURNS: key type for dict, unknown otherwise

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn getKeyType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .dict => t.dict.key.*,
        else => .unknown,
    };
}
