//! isCallable - Check if type is a callable (function, lambda, method)
//! USE: When checking if a value can be called with ()
//! RETURNS: true for .callable type

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isCallable(t: NativeType) bool {
    return t == .callable;
}
