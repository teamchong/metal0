//! CPython source: Lib/decimal.py
//!
//! Provides support for fast correctly-rounded decimal floating point arithmetic.
//!
//! Mirrors: CPython Lib/decimal.py

// Re-export types
pub const types = @import("decimal/types.zig");
pub const RoundingMode = types.RoundingMode;
pub const Signal = types.Signal;

// Re-export context
pub const context_mod = @import("decimal/context.zig");
pub const Context = context_mod.Context;
pub const default_context = &context_mod.default_context;
pub const getcontext = context_mod.getcontext;
pub const setcontext = context_mod.setcontext;
pub const BasicContext = context_mod.BasicContext;
pub const ExtendedContext = context_mod.ExtendedContext;

// Re-export Decimal class
pub const decimal_class = @import("decimal/decimal_class.zig");
pub const Decimal = decimal_class.Decimal;

// Re-export constants
pub const constants = @import("decimal/constants.zig");
pub const ZERO = constants.ZERO;
pub const ONE = constants.ONE;
pub const TEN = constants.TEN;
pub const INFINITY = constants.INFINITY;
pub const NEG_INFINITY = constants.NEG_INFINITY;
pub const NAN = constants.NAN;
