//! isClassInstance - Check if type is a class instance
//! USE: When checking for custom class objects that may have dunder methods
//! RETURNS: true for .class_instance type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isClassInstance(t: NativeType) bool {
    return t == .class_instance;
}
