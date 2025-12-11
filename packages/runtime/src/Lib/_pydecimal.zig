/// _pydecimal - Python Decimal Implementation
/// Mirrors cpython/Lib/_pydecimal.py
///
/// Pure Zig implementation of the Decimal type.
/// Provides arbitrary-precision decimal floating point arithmetic.
///
/// Module structure:
/// - types.zig       : Rounding, Signal, SpecialValue enums
/// - constants.zig   : Precision and exponent limits
/// - decimal.zig     : Decimal type and operations
/// - context.zig     : Context for arithmetic behavior
/// - module.zig      : Module-level state management

const types = @import("_pydecimal/types.zig");
const constants = @import("_pydecimal/constants.zig");
const decimal = @import("_pydecimal/decimal.zig");
const context = @import("_pydecimal/context.zig");
const module_state = @import("_pydecimal/module.zig");

// ============================================================================
// Re-export Types
// ============================================================================

pub const Rounding = types.Rounding;
pub const Signal = types.Signal;
pub const SignalFlags = types.SignalFlags;
pub const SpecialValue = types.SpecialValue;

// ============================================================================
// Re-export Constants
// ============================================================================

pub const MAX_PREC = constants.MAX_PREC;
pub const MAX_EMAX = constants.MAX_EMAX;
pub const MIN_EMIN = constants.MIN_EMIN;
pub const DEFAULT_PREC = constants.DEFAULT_PREC;

// ============================================================================
// Re-export Decimal
// ============================================================================

pub const Decimal = decimal.Decimal;

// ============================================================================
// Re-export Context
// ============================================================================

pub const Context = context.Context;

// ============================================================================
// Re-export Module Functions
// ============================================================================

pub const init = module_state.init;
pub const getContext = module_state.getContext;
pub const setContext = module_state.setContext;
pub const reset = module_state.reset;

// ============================================================================
// Tests (re-export from submodules)
// ============================================================================

test {
    @import("std").testing.refAllDecls(@This());
}
