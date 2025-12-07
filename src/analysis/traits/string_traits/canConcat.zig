//! canConcat - Check if two types can be concatenated with +
//! USE: Before emitting str + str or bytes + bytes
//! VALID: str + str, bytes + bytes
//! INVALID: str + bytes (Python raises TypeError)

const NativeType = @import("../../native_types/core.zig").NativeType;
const isString = @import("isString.zig").isString;
const isBytes = @import("isBytes.zig").isBytes;

pub fn canConcat(left: NativeType, right: NativeType) bool {
    if (isString(left) and isString(right)) return true;
    if (isBytes(left) and isBytes(right)) return true;
    return false;
}
