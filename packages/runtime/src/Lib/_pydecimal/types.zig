/// _pydecimal.types - Type definitions for decimal arithmetic
/// Defines Rounding modes, Signals, and special value types

const std = @import("std");

// ============================================================================
// Rounding Modes
// ============================================================================

/// Decimal rounding modes - determines how values are rounded when precision is exceeded
pub const Rounding = enum {
    round_ceiling, // Round towards Infinity
    round_down, // Round towards zero
    round_floor, // Round towards -Infinity
    round_half_down, // Round to nearest, ties go towards zero
    round_half_even, // Round to nearest, ties go to even (banker's)
    round_half_up, // Round to nearest, ties go away from zero
    round_up, // Round away from zero
    round_05up, // Round away from zero if last digit is 0 or 5

    /// Parse rounding mode from string
    pub fn fromString(s: []const u8) ?Rounding {
        const map = std.StaticStringMap(Rounding).initComptime(.{
            .{ "ROUND_CEILING", .round_ceiling },
            .{ "ROUND_DOWN", .round_down },
            .{ "ROUND_FLOOR", .round_floor },
            .{ "ROUND_HALF_DOWN", .round_half_down },
            .{ "ROUND_HALF_EVEN", .round_half_even },
            .{ "ROUND_HALF_UP", .round_half_up },
            .{ "ROUND_UP", .round_up },
            .{ "ROUND_05UP", .round_05up },
        });
        return map.get(s);
    }
};

// ============================================================================
// Signals/Flags
// ============================================================================

/// Decimal operation signals/exceptions
pub const Signal = enum {
    clamped, // Exponent has been clamped to context range
    invalid_operation, // Invalid operation performed
    division_by_zero, // Division by zero
    inexact, // Result is inexact
    rounded, // Result was rounded
    subnormal, // Result is subnormal
    overflow, // Exponent overflow
    underflow, // Exponent underflow
    float_operation, // Operation on float

    /// Get display name for signal
    pub fn getName(self: Signal) []const u8 {
        return switch (self) {
            .clamped => "Clamped",
            .invalid_operation => "InvalidOperation",
            .division_by_zero => "DivisionByZero",
            .inexact => "Inexact",
            .rounded => "Rounded",
            .subnormal => "Subnormal",
            .overflow => "Overflow",
            .underflow => "Underflow",
            .float_operation => "FloatOperation",
        };
    }
};

/// Set of active signal flags
pub const SignalFlags = std.EnumSet(Signal);

// ============================================================================
// Special Values
// ============================================================================

/// Decimal special value types (not normal finite numbers)
pub const SpecialValue = enum {
    normal, // Normal finite decimal number
    infinity, // Positive or negative infinity
    nan, // Quiet NaN (non-signaling)
    snan, // Signaling NaN (triggers on use)
};

// ============================================================================
// Tests
// ============================================================================

test "rounding mode from string" {
    try std.testing.expectEqual(Rounding.round_half_even, Rounding.fromString("ROUND_HALF_EVEN").?);
    try std.testing.expectEqual(Rounding.round_down, Rounding.fromString("ROUND_DOWN").?);
    try std.testing.expect(Rounding.fromString("INVALID") == null);
}

test "signal names" {
    try std.testing.expectEqualStrings("InvalidOperation", Signal.invalid_operation.getName());
    try std.testing.expectEqualStrings("DivisionByZero", Signal.division_by_zero.getName());
}
