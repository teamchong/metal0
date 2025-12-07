//! supportsEncode - Check if type supports .encode() method
//! USE: Before emitting str.encode() -> bytes
//! RETURNS: true for string only

const NativeType = @import("../../native_types/core.zig").NativeType;
const isString = @import("isString.zig").isString;

pub fn supportsEncode(t: NativeType) bool {
    return isString(t);
}
