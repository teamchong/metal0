/// Float operations for runtime
/// Re-exports from float_ops/ submodules for backwards compatibility

// Submodule imports
const arithmetic = @import("float_ops/arithmetic.zig");
const rounding = @import("float_ops/rounding.zig");
const ratio = @import("float_ops/ratio.zig");
const hex = @import("float_ops/hex.zig");
const conversion = @import("float_ops/conversion.zig");
const parsing = @import("float_ops/parsing.zig");
const builtins = @import("float_ops/builtins.zig");

// ============================================================================
// Re-exports from arithmetic.zig
// ============================================================================
pub const PythonError = arithmetic.PythonError;
pub const pyFloatMod = arithmetic.pyFloatMod;
pub const numToFloat = arithmetic.numToFloat;
pub const subtractNum = arithmetic.subtractNum;
pub const addNum = arithmetic.addNum;
pub const mulNum = arithmetic.mulNum;
pub const divideFloat = arithmetic.divideFloat;

// ============================================================================
// Re-exports from rounding.zig
// ============================================================================
pub const IntResult = rounding.IntResult;
pub const FloorCeilResult = rounding.FloorCeilResult;
pub const floatFloorBig = rounding.floatFloorBig;
pub const floatFloor = rounding.floatFloor;
pub const floatFloorAny = rounding.floatFloorAny;
pub const floatCeilBig = rounding.floatCeilBig;
pub const floatCeil = rounding.floatCeil;
pub const floatCeilAny = rounding.floatCeilAny;
pub const floatTrunc = rounding.floatTrunc;
pub const floatRound = rounding.floatRound;

// ============================================================================
// Re-exports from ratio.zig
// ============================================================================
pub const IntegerRatioResult = ratio.IntegerRatioResult;
pub const floatAsIntegerRatioBigInt = ratio.floatAsIntegerRatioBigInt;
pub const floatAsIntegerRatio = ratio.floatAsIntegerRatio;

// ============================================================================
// Re-exports from hex.zig
// ============================================================================
pub const floatFromHex = hex.floatFromHex;
pub const floatHex = hex.floatHex;
pub const floatToHex = hex.floatToHex;

// ============================================================================
// Re-exports from conversion.zig
// ============================================================================
pub const floatGetFormat = conversion.floatGetFormat;
pub const floatIsInteger = conversion.floatIsInteger;
pub const pyFloat = conversion.pyFloat;
pub const toFloat = conversion.toFloat;

// ============================================================================
// Re-exports from parsing.zig
// ============================================================================
pub const parseFloatStr = parsing.parseFloatStr;
pub const parseFloatBytes = parsing.parseFloatBytes;
pub const parseFloatWithUnicode = parsing.parseFloatWithUnicode;

// ============================================================================
// Re-exports from builtins.zig
// ============================================================================
pub const floatBuiltinCall = builtins.floatBuiltinCall;
pub const boolBuiltinCall = builtins.boolBuiltinCall;
