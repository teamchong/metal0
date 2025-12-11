//! CPython source: Lib/numbers.py
//!
//! Defines the hierarchy of numeric abstract base classes:
//! Number :> Complex :> Real :> Rational :> Integral
//!
//! Mirrors: CPython Lib/numbers.py

// Re-export all types
pub const Number = @import("numbers/types.zig").Number;
pub const Complex = @import("numbers/complex.zig").Complex;
pub const Real = @import("numbers/real.zig").Real;
pub const Rational = @import("numbers/rational.zig").Rational;
pub const Integral = @import("numbers/integral.zig").Integral;

// Re-export utility functions
pub const gcd = @import("numbers/utils.zig").gcd;

// Re-export type checking functions
pub const isNumber = @import("numbers/type_checking.zig").isNumber;
pub const isComplex = @import("numbers/type_checking.zig").isComplex;
pub const isReal = @import("numbers/type_checking.zig").isReal;
pub const isRational = @import("numbers/type_checking.zig").isRational;
pub const isIntegral = @import("numbers/type_checking.zig").isIntegral;

// Re-export tests to ensure they run
test {
    _ = @import("numbers/complex.zig");
    _ = @import("numbers/real.zig");
    _ = @import("numbers/rational.zig");
    _ = @import("numbers/integral.zig");
    _ = @import("numbers/type_checking.zig");
}
