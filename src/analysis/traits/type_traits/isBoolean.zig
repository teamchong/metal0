//! isBoolean - Check if type is boolean
//! USE: When checking if/while conditions without truthiness conversion
//! RETURNS: true for .bool type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isBoolean(t: NativeType) bool {
    return t == .bool;
}
