//! isStringLike - Check if type is string or bytes
//! USE: For operations that work on both (len, concat, iteration)
//! RETURNS: true for string, bytes

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isStringLike(t: NativeType) bool {
    return t == .string or t == .bytes;
}
