//! isCallable - Check if type is a callable (function, lambda, method)
//! USE: When checking if a value can be called with ()
//! RETURNS: true for .callable, .function, .closure types

const NativeType = @import("../../native_types/core.zig").NativeType;

pub fn isCallable(t: NativeType) bool {
    return switch (t) {
        .callable, .function, .closure => true,
        else => false,
    };
}
