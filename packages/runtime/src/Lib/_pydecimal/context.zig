/// _pydecimal.context - Decimal context for controlling arithmetic behavior
/// Manages precision, rounding mode, exponent limits, and signal handling

const types = @import("types.zig");
const constants = @import("constants.zig");

pub const Rounding = types.Rounding;
pub const Signal = types.Signal;
pub const SignalFlags = types.SignalFlags;
pub const DEFAULT_PREC = constants.DEFAULT_PREC;

// ============================================================================
// Context
// ============================================================================

/// Decimal context - controls precision, rounding, and exception handling
pub const Context = struct {
    const Self = @This();

    /// Precision (significant digits)
    prec: u32 = DEFAULT_PREC,
    /// Rounding mode
    rounding: Rounding = .round_half_even,
    /// Maximum exponent
    emax: i32 = 999999,
    /// Minimum exponent
    emin: i32 = -999999,
    /// Capitals (E vs e in output)
    capitals: bool = true,
    /// Clamp exponents to range
    clamp: bool = false,
    /// Raised signals
    flags: SignalFlags = SignalFlags{},
    /// Enabled traps
    traps: SignalFlags = SignalFlags.initFull(),

    /// Get basic context
    pub fn basicContext() Self {
        return Self{
            .prec = 9,
            .rounding = .round_half_up,
            .emax = 999999,
            .emin = -999999,
        };
    }

    /// Get extended context
    pub fn extendedContext() Self {
        return Self{
            .prec = 9,
            .rounding = .round_half_even,
            .emax = 999999,
            .emin = -999999,
            .traps = SignalFlags{},
        };
    }

    /// Clear flags
    pub fn clearFlags(self: *Self) void {
        self.flags = SignalFlags{};
    }

    /// Raise a signal
    pub fn raiseSignal(self: *Self, signal: Signal) !void {
        self.flags.insert(signal);
        if (self.traps.contains(signal)) {
            return error.DecimalException;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "context basic" {
    const std = @import("std");
    const ctx = Context.basicContext();
    try std.testing.expectEqual(@as(u32, 9), ctx.prec);
    try std.testing.expectEqual(Rounding.round_half_up, ctx.rounding);
}
