//! isUnknown - Check if type is dynamic/unknown
//! USE: When deciding if runtime dispatch (PyObject) is needed
//! RETURNS: true for .unknown type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isUnknown(t: NativeType) bool {
    return t == .unknown;
}
