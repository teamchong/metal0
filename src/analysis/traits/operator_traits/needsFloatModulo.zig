//! needsFloatModulo - Check if % needs Python float semantics
//! USE: Before emitting a % b with floats
//! RETURNS: true if should use runtime.pyFloatMod

const NativeType = @import("../../native_types/core.zig").NativeType;
const getModuloSemantics = @import("getModuloSemantics.zig").getModuloSemantics;

pub fn needsFloatModulo(left: NativeType, right: NativeType) bool {
    return getModuloSemantics(left, right) == .python_floored;
}
