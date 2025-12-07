//! getReprPrefix - Get repr prefix for type
//! USE: When emitting string literals in repr output
//! RETURNS: "b'" for bytes, "'" for string

const NativeType = @import("../../native_types/core.zig").NativeType;
const isBytes = @import("isBytes.zig").isBytes;

pub fn getReprPrefix(t: NativeType) []const u8 {
    return if (isBytes(t)) "b'" else "'";
}
