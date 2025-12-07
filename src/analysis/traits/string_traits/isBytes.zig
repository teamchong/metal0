//! isBytes - Check if type is bytes (not string)
//! USE: When bytes-specific handling needed (b'...' repr)
//! RETURNS: true for bytes

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isBytes(t: NativeType) bool {
    return t == .bytes;
}
