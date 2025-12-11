//! Context for decimal operations
//! Manages precision, rounding mode, and exception handling

const std = @import("std");
const types = @import("types.zig");

pub const RoundingMode = types.RoundingMode;
pub const Signal = types.Signal;

/// Context for decimal operations
pub const Context = struct {
    const Self = @This();

    prec: u32 = 28, // Precision (number of significant digits)
    rounding: RoundingMode = .ROUND_HALF_EVEN,
    Emin: i32 = -999999,
    Emax: i32 = 999999,
    capitals: bool = true, // Use 'E' vs 'e' in string representation
    clamp: bool = false,

    // Signal traps (which signals raise exceptions)
    traps: [9]bool = .{ false, true, false, true, true, false, false, false, false },

    // Signal flags (which signals have been triggered)
    flags: [9]bool = .{false} ** 9,

    pub fn setTrap(self: *Self, signal: Signal, value: bool) void {
        self.traps[@intFromEnum(signal)] = value;
    }

    pub fn getTrap(self: Self, signal: Signal) bool {
        return self.traps[@intFromEnum(signal)];
    }

    pub fn setFlag(self: *Self, signal: Signal) void {
        self.flags[@intFromEnum(signal)] = true;
    }

    pub fn getFlag(self: Self, signal: Signal) bool {
        return self.flags[@intFromEnum(signal)];
    }

    pub fn clearFlags(self: *Self) void {
        self.flags = .{false} ** 9;
    }

    pub fn copy(self: Self) Self {
        return self;
    }
};

/// Default context
pub var default_context = Context{};

/// Get the current context (thread-local would be better, but this is simpler)
pub fn getcontext() *Context {
    return &default_context;
}

/// Set the current context
pub fn setcontext(ctx: Context) void {
    default_context = ctx;
}

/// Create a basic context with minimal settings
pub fn BasicContext() Context {
    var ctx = Context{};
    ctx.prec = 9;
    ctx.rounding = .ROUND_HALF_UP;
    ctx.setTrap(.DivisionByZero, true);
    ctx.setTrap(.Overflow, true);
    ctx.setTrap(.InvalidOperation, true);
    ctx.setTrap(.Clamped, false);
    ctx.setTrap(.Underflow, false);
    return ctx;
}

/// Create an extended context for more precision
pub fn ExtendedContext() Context {
    var ctx = Context{};
    ctx.prec = 9;
    ctx.rounding = .ROUND_HALF_EVEN;
    // All traps off
    ctx.traps = .{false} ** 9;
    return ctx;
}

// ============================================================================
// Tests
// ============================================================================

test "Context" {
    var ctx = getcontext().*;
    try std.testing.expectEqual(@as(u32, 28), ctx.prec);

    ctx.prec = 50;
    setcontext(ctx);
    try std.testing.expectEqual(@as(u32, 50), getcontext().prec);

    // Reset
    setcontext(Context{});
}
