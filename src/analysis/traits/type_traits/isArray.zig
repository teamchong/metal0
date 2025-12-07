//! isArray - Check if type is a fixed-size array
//! USE: When checking for array type (as opposed to dynamic list)
//! RETURNS: true for .array type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isArray(t: NativeType) bool {
    return t == .array;
}
