//! Decimal constants
//! Common decimal values for convenience

const decimal_class = @import("decimal_class.zig");
pub const Decimal = decimal_class.Decimal;

pub const ZERO = Decimal{ .coefficient = 0, .exponent = 0 };
pub const ONE = Decimal{ .coefficient = 1, .exponent = 0 };
pub const TEN = Decimal{ .coefficient = 10, .exponent = 0 };
pub const INFINITY = Decimal{ .special = .Infinity };
pub const NEG_INFINITY = Decimal{ .sign = true, .special = .Infinity };
pub const NAN = Decimal{ .special = .NaN };

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "Special values" {
    try std.testing.expect(INFINITY.isInfinite());
    try std.testing.expect(NAN.isNaN());
    try std.testing.expect(ZERO.isZero());
    try std.testing.expect(ONE.isFinite());
}
