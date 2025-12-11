//! Utility functions for numeric operations
//!
//! Provides helper functions like gcd (greatest common divisor).

const std = @import("std");

/// Greatest common divisor
pub fn gcd(a: anytype, b: anytype) @TypeOf(a) {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;

    while (y != 0) {
        const t = y;
        y = @rem(x, y);
        x = t;
    }
    return x;
}
