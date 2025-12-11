//! Core types for decimal arithmetic
//! Defines RoundingMode, Signal, and Special value types

const std = @import("std");

/// Rounding modes
pub const RoundingMode = enum {
    ROUND_CEILING, // Round towards positive infinity
    ROUND_DOWN, // Round towards zero
    ROUND_FLOOR, // Round towards negative infinity
    ROUND_HALF_DOWN, // Round to nearest, ties go towards zero
    ROUND_HALF_EVEN, // Round to nearest, ties go to even (banker's rounding)
    ROUND_HALF_UP, // Round to nearest, ties go away from zero
    ROUND_UP, // Round away from zero
    ROUND_05UP, // Round away from zero if last digit is 0 or 5
};

/// Signals that can be trapped
pub const Signal = enum {
    Clamped,
    DivisionByZero,
    Inexact,
    InvalidOperation,
    Overflow,
    Rounded,
    Subnormal,
    Underflow,
    FloatOperation,
};

/// Special value types for Decimal
pub const Special = enum {
    Normal,
    Infinity,
    NaN,
    sNaN, // Signaling NaN
};
