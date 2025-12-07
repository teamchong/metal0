//! canRepeat - Check if type can be repeated with * int
//! USE: Before emitting "ab" * 3 or b"ab" * 3
//! RETURNS: true for string, bytes

const NativeType = @import("../../native_types/core.zig").NativeType;
const isStringLike = @import("isStringLike.zig").isStringLike;

pub fn canRepeat(t: NativeType) bool {
    return isStringLike(t);
}
