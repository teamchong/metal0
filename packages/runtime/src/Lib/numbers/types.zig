//! Core types for the numeric tower
//!
//! Defines the Number type tag and data union used throughout the numeric hierarchy.

const std = @import("std");

/// Abstract base class for numeric types.
/// All numeric types should be registered as virtual subclasses of Number.
pub const Number = struct {
    /// Type tag for runtime type checking
    pub const Tag = enum {
        integral,
        rational,
        real,
        complex,
    };

    tag: Tag,
    data: Data,

    pub const Data = union {
        integral: i64,
        rational: struct { numerator: i64, denominator: i64 },
        real: f64,
        complex: struct { real: f64, imag: f64 },
    };

    /// Check if a value is an instance of Number
    pub fn isNumber(comptime T: type) bool {
        return @typeInfo(T) == .int or
            @typeInfo(T) == .float or
            @typeInfo(T) == .comptime_int or
            @typeInfo(T) == .comptime_float;
    }
};
