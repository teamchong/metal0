//! needsFloatFloorDiv - Check if // needs Python float semantics
//! USE: Before emitting a // b with floats
//! RETURNS: true if should use @floor(a/b) instead of @divFloor

const NativeType = @import("../../native_types/core.zig").NativeType;
const getFloorDivSemantics = @import("getFloorDivSemantics.zig").getFloorDivSemantics;

pub fn needsFloatFloorDiv(left: NativeType, right: NativeType) bool {
    return getFloorDivSemantics(left, right) == .python_floored;
}
