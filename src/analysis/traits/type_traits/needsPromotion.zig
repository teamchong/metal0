//! needsPromotion - Check if operands need type conversion before operation
//! USE: Before mixed-type arithmetic (int + float)
//! RETURNS: true if left and right are different numeric types

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const isNumeric = @import("isNumeric.zig").isNumeric;

pub fn needsPromotion(left: NativeType, right: NativeType) bool {
    if (!isNumeric(left) or !isNumeric(right)) return false;
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);
    return left_tag != right_tag;
}
