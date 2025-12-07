//! supportsDecode - Check if type supports .decode() method
//! USE: Before emitting bytes.decode() -> str
//! RETURNS: true for bytes only

const NativeType = @import("../../native_types/core.zig").NativeType;
const isBytes = @import("isBytes.zig").isBytes;

pub fn supportsDecode(t: NativeType) bool {
    return isBytes(t);
}
