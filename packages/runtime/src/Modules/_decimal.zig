/// Python _decimal module - C extension for decimal arithmetic
/// This is the Zig implementation of CPython's Modules/_decimal/
///
/// The _decimal module provides the C implementation of the decimal module,
/// offering high-performance arbitrary precision decimal arithmetic.
const std = @import("std");

// Re-export from _pydecimal for compatibility
const _pydecimal = @import("../Lib/_pydecimal.zig");

// Export all public symbols from _pydecimal
pub const MAX_EMAX = _pydecimal.MAX_EMAX;
pub const MIN_EMIN = _pydecimal.MIN_EMIN;
pub const MIN_ETINY = _pydecimal.MIN_ETINY;
pub const MAX_PREC = _pydecimal.MAX_PREC;

pub const RoundingMode = _pydecimal.RoundingMode;
pub const ROUND_HALF_EVEN = _pydecimal.ROUND_HALF_EVEN;

pub const Signal = _pydecimal.Signal;
pub const Context = _pydecimal.Context;
pub const Decimal = _pydecimal.Decimal;

pub const BasicContext = _pydecimal.BasicContext;
pub const ExtendedContext = _pydecimal.ExtendedContext;
pub const DefaultContext = _pydecimal.DefaultContext;

pub const getcontext = _pydecimal.getcontext;
pub const setcontext = _pydecimal.setcontext;
pub const localcontext = _pydecimal.localcontext;

/// Module name
pub const __name__: []const u8 = "_decimal";

/// Check if the C implementation is available (always true for metal0)
pub const HAVE_THREADS: bool = true;

/// IEEE context factory functions
pub fn IEEE_CONTEXT_MAX_BITS() u32 {
    return 512;
}

/// Create an IEEE context for a given bit width
pub fn IEEEContext(bits: u32) Context {
    var ctx = Context.init();
    switch (bits) {
        32 => {
            ctx.prec = 7;
            ctx.Emax = 96;
            ctx.Emin = -95;
        },
        64 => {
            ctx.prec = 16;
            ctx.Emax = 384;
            ctx.Emin = -383;
        },
        128 => {
            ctx.prec = 34;
            ctx.Emax = 6144;
            ctx.Emin = -6143;
        },
        else => {
            // Default IEEE context
        },
    }
    return ctx;
}

/// DecimalTuple - immutable representation of a Decimal
pub const DecimalTuple = struct {
    sign: i8,
    digits: []const u8,
    exponent: i64,

    pub fn init(sign: i8, digits: []const u8, exponent: i64) DecimalTuple {
        return .{
            .sign = sign,
            .digits = digits,
            .exponent = exponent,
        };
    }
};

/// Convert Decimal to DecimalTuple
pub fn as_tuple(d: *const Decimal) DecimalTuple {
    return DecimalTuple.init(d.sign, d.int, d.exp);
}

/// Test functions for verification
pub fn test_basic() bool {
    const d = Decimal.from_int(123);
    return d.sign == 0 and d.exp == 0;
}
