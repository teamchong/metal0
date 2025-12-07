//! getRepeatResultType - Get result type of string/bytes repetition
//! USE: When inferring type of "ab" * 3
//! RETURNS: null if repeat invalid, else string or bytes

const NativeType = @import("../../native_types/core.zig").NativeType;
const isString = @import("isString.zig").isString;
const isBytes = @import("isBytes.zig").isBytes;

pub fn getRepeatResultType(t: NativeType) ?NativeType {
    if (isString(t)) return .{ .string = .runtime };
    if (isBytes(t)) return .bytes;
    return null;
}
