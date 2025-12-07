//! isString - Check if type is string (not bytes)
//! USE: When string-specific handling needed (encode)
//! RETURNS: true for string

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isString(t: NativeType) bool {
    return t == .string;
}
