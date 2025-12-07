//! getConcatResultType - Get result type of string/bytes concatenation
//! USE: When inferring type of str + str or bytes + bytes
//! RETURNS: null if concat invalid, else string or bytes

const NativeType = @import("../../native_types/core.zig").NativeType;
const isString = @import("isString.zig").isString;
const isBytes = @import("isBytes.zig").isBytes;

pub fn getConcatResultType(left: NativeType, right: NativeType) ?NativeType {
    if (isString(left) and isString(right)) return .{ .string = .runtime };
    if (isBytes(left) and isBytes(right)) return .bytes;
    return null;
}
