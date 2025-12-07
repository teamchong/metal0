//! isMapping - Check if type is key-value mapping
//! USE: Before emitting .keys(), .values(), .items(), or dict[key]=val
//! RETURNS: true for dict

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isMapping(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .dict;
}
