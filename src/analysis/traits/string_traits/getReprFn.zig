//! getReprFn - Get runtime repr function name for type
//! USE: When emitting repr() calls
//! RETURNS: "bytesRepr" for bytes, "stringRepr" otherwise

const NativeType = @import("../../native_types/core.zig").NativeType;
const isBytes = @import("isBytes.zig").isBytes;

pub fn getReprFn(t: NativeType) []const u8 {
    return if (isBytes(t)) "bytesRepr" else "stringRepr";
}
