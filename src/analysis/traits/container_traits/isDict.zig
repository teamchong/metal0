//! isDict - Check if type is a dict
//! USE: Before emitting .keys(), .values(), dict[k]=v
//! RETURNS: true for dict

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isDict(t: NativeType) bool {
    return t == .dict;
}
