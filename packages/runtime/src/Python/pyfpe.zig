/// pyfpe - Floating Point Exception Handling
/// Mirrors cpython/Python/pyfpe.c
///
/// This module provides floating-point exception handling:
/// - FPE signal handling
/// - IEEE 754 exception detection
/// - Error flag management
/// - Platform-specific FPU control

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// FPE Exception Types
// ============================================================================

/// Floating-point exception types
pub const FPException = enum(u8) {
    none = 0,
    invalid = 1, // Invalid operation (e.g., 0/0, sqrt(-1))
    divide_by_zero = 2, // Division by zero
    overflow = 4, // Overflow
    underflow = 8, // Underflow
    inexact = 16, // Inexact result
    denormal = 32, // Denormal operand

    pub fn fromMask(mask: u8) FPException {
        return @enumFromInt(mask);
    }

    pub fn toMask(self: FPException) u8 {
        return @intFromEnum(self);
    }
};

/// Rounding modes
pub const RoundingMode = enum(u8) {
    nearest = 0, // Round to nearest, ties to even
    downward = 1, // Round toward -infinity
    upward = 2, // Round toward +infinity
    toward_zero = 3, // Round toward zero

    pub fn fromBits(bits: u8) RoundingMode {
        return @enumFromInt(bits & 3);
    }
};

// ============================================================================
// FPE State
// ============================================================================

/// Thread-local FPE state
pub const FPEState = struct {
    /// Exception flags that have been raised
    raised: u8 = 0,
    /// Exception mask (which exceptions to track)
    mask: u8 = 0xFF,
    /// Current rounding mode
    rounding: RoundingMode = .nearest,
    /// Whether FPE handling is enabled
    enabled: bool = false,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Check if any exception was raised
    pub fn hasException(self: *const Self) bool {
        return (self.raised & self.mask) != 0;
    }

    /// Check if specific exception was raised
    pub fn isRaised(self: *const Self, exc: FPException) bool {
        return (self.raised & exc.toMask()) != 0;
    }

    /// Raise an exception
    pub fn raise(self: *Self, exc: FPException) void {
        self.raised |= exc.toMask();
    }

    /// Clear all exceptions
    pub fn clear(self: *Self) void {
        self.raised = 0;
    }

    /// Clear specific exception
    pub fn clearException(self: *Self, exc: FPException) void {
        self.raised &= ~exc.toMask();
    }

    /// Set exception mask
    pub fn setMask(self: *Self, mask: u8) void {
        self.mask = mask;
    }

    /// Get raised exceptions
    pub fn getRaised(self: *const Self) u8 {
        return self.raised;
    }
};

// ============================================================================
// Thread-Local State
// ============================================================================

threadlocal var tls_fpe_state: FPEState = FPEState.init();

/// Get thread-local FPE state
pub fn getState() *FPEState {
    return &tls_fpe_state;
}

// ============================================================================
// FPE Control Functions
// ============================================================================

/// Start FPE checking
pub fn startCheck() void {
    const state = getState();
    state.enabled = true;
    state.clear();
}

/// Stop FPE checking and return raised exceptions
pub fn stopCheck() u8 {
    const state = getState();
    const raised = state.raised;
    state.enabled = false;
    state.clear();
    return raised;
}

/// Check if FPE occurred and clear
pub fn checkAndClear() bool {
    const state = getState();
    const had_exception = state.hasException();
    state.clear();
    return had_exception;
}

// ============================================================================
// IEEE 754 Detection
// ============================================================================

/// Check if value is infinity
pub fn isInf(value: f64) bool {
    return std.math.isInf(value);
}

/// Check if value is positive infinity
pub fn isPosInf(value: f64) bool {
    return value == std.math.inf(f64);
}

/// Check if value is negative infinity
pub fn isNegInf(value: f64) bool {
    return value == -std.math.inf(f64);
}

/// Check if value is NaN
pub fn isNan(value: f64) bool {
    return std.math.isNan(value);
}

/// Check if value is finite
pub fn isFinite(value: f64) bool {
    return std.math.isFinite(value);
}

/// Check if value is subnormal (denormal)
pub fn isSubnormal(value: f64) bool {
    const bits = @as(u64, @bitCast(value));
    const exp = (bits >> 52) & 0x7FF;
    const mantissa = bits & 0xFFFFFFFFFFFFF;
    return exp == 0 and mantissa != 0;
}

/// Check if value is zero
pub fn isZero(value: f64) bool {
    return value == 0.0 or value == -0.0;
}

/// Get sign of value (-1, 0, or 1)
pub fn getSign(value: f64) i32 {
    if (isNan(value)) return 0;
    if (value > 0) return 1;
    if (value < 0) return -1;
    // Check for negative zero
    const bits = @as(u64, @bitCast(value));
    if ((bits >> 63) != 0) return -1;
    return 0;
}

// ============================================================================
// Safe Math Operations
// ============================================================================

/// Safe division with exception detection
pub fn safeDivide(a: f64, b: f64) struct { result: f64, exception: ?FPException } {
    if (b == 0.0) {
        if (a == 0.0) {
            return .{ .result = std.math.nan(f64), .exception = .invalid };
        }
        const result = if (a > 0) std.math.inf(f64) else -std.math.inf(f64);
        return .{ .result = result, .exception = .divide_by_zero };
    }

    const result = a / b;

    if (isNan(result) and !isNan(a) and !isNan(b)) {
        return .{ .result = result, .exception = .invalid };
    }
    if (isInf(result) and isFinite(a) and isFinite(b)) {
        return .{ .result = result, .exception = .overflow };
    }

    return .{ .result = result, .exception = null };
}

/// Safe multiplication with overflow detection
pub fn safeMultiply(a: f64, b: f64) struct { result: f64, exception: ?FPException } {
    const result = a * b;

    if (isNan(result) and !isNan(a) and !isNan(b)) {
        return .{ .result = result, .exception = .invalid };
    }
    if (isInf(result) and isFinite(a) and isFinite(b)) {
        return .{ .result = result, .exception = .overflow };
    }
    if (result == 0 and a != 0 and b != 0) {
        return .{ .result = result, .exception = .underflow };
    }

    return .{ .result = result, .exception = null };
}

/// Safe addition
pub fn safeAdd(a: f64, b: f64) struct { result: f64, exception: ?FPException } {
    const result = a + b;

    if (isNan(result) and !isNan(a) and !isNan(b)) {
        return .{ .result = result, .exception = .invalid };
    }
    if (isInf(result) and isFinite(a) and isFinite(b)) {
        return .{ .result = result, .exception = .overflow };
    }

    return .{ .result = result, .exception = null };
}

/// Safe subtraction
pub fn safeSubtract(a: f64, b: f64) struct { result: f64, exception: ?FPException } {
    const result = a - b;

    if (isNan(result) and !isNan(a) and !isNan(b)) {
        return .{ .result = result, .exception = .invalid };
    }
    if (isInf(result) and isFinite(a) and isFinite(b)) {
        return .{ .result = result, .exception = .overflow };
    }

    return .{ .result = result, .exception = null };
}

// ============================================================================
// Platform-Specific FPU Control
// ============================================================================

/// Get FPU control word (platform-specific)
pub fn getFPUControl() u32 {
    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .x86) {
        var control: u16 = undefined;
        asm volatile ("fnstcw %[control]"
            : [control] "=m" (control)
        );
        return control;
    }
    return 0;
}

/// Set FPU control word (platform-specific)
pub fn setFPUControl(control: u32) void {
    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .x86) {
        const ctrl: u16 = @truncate(control);
        asm volatile ("fldcw %[control]"
            :
            : [control] "m" (ctrl)
        );
    }
}

/// Get MXCSR (SSE control register)
pub fn getMXCSR() u32 {
    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .x86) {
        var mxcsr: u32 = undefined;
        asm volatile ("stmxcsr %[mxcsr]"
            : [mxcsr] "=m" (mxcsr)
        );
        return mxcsr;
    }
    return 0;
}

/// Set MXCSR
pub fn setMXCSR(mxcsr: u32) void {
    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .x86) {
        asm volatile ("ldmxcsr %[mxcsr]"
            :
            : [mxcsr] "m" (mxcsr)
        );
    }
}

// ============================================================================
// Python-Compatible Functions
// ============================================================================

/// Matches Python's Py_FPE_START_PROTECT
pub fn PyFPEStart() void {
    startCheck();
}

/// Matches Python's Py_FPE_END_PROTECT
pub fn PyFPEEnd(result: f64) !f64 {
    const state = getState();
    if (state.hasException()) {
        _ = stopCheck();
        return error.FloatingPointError;
    }
    return result;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "fpe state basic" {
    var state = FPEState.init();
    try std.testing.expect(!state.hasException());

    state.raise(.divide_by_zero);
    try std.testing.expect(state.hasException());
    try std.testing.expect(state.isRaised(.divide_by_zero));
    try std.testing.expect(!state.isRaised(.overflow));

    state.raise(.overflow);
    try std.testing.expect(state.isRaised(.overflow));

    state.clearException(.divide_by_zero);
    try std.testing.expect(!state.isRaised(.divide_by_zero));
    try std.testing.expect(state.isRaised(.overflow));

    state.clear();
    try std.testing.expect(!state.hasException());
}

test "ieee 754 detection" {
    try std.testing.expect(isInf(std.math.inf(f64)));
    try std.testing.expect(isInf(-std.math.inf(f64)));
    try std.testing.expect(!isInf(1.0));

    try std.testing.expect(isPosInf(std.math.inf(f64)));
    try std.testing.expect(!isPosInf(-std.math.inf(f64)));

    try std.testing.expect(isNegInf(-std.math.inf(f64)));
    try std.testing.expect(!isNegInf(std.math.inf(f64)));

    try std.testing.expect(isNan(std.math.nan(f64)));
    try std.testing.expect(!isNan(1.0));

    try std.testing.expect(isFinite(1.0));
    try std.testing.expect(!isFinite(std.math.inf(f64)));
    try std.testing.expect(!isFinite(std.math.nan(f64)));

    try std.testing.expect(isZero(0.0));
    try std.testing.expect(isZero(-0.0));
    try std.testing.expect(!isZero(1.0));
}

test "safe divide" {
    const result1 = safeDivide(10.0, 2.0);
    try std.testing.expectEqual(@as(f64, 5.0), result1.result);
    try std.testing.expect(result1.exception == null);

    const result2 = safeDivide(1.0, 0.0);
    try std.testing.expect(isInf(result2.result));
    try std.testing.expectEqual(FPException.divide_by_zero, result2.exception.?);

    const result3 = safeDivide(0.0, 0.0);
    try std.testing.expect(isNan(result3.result));
    try std.testing.expectEqual(FPException.invalid, result3.exception.?);
}

test "sign detection" {
    try std.testing.expectEqual(@as(i32, 1), getSign(5.0));
    try std.testing.expectEqual(@as(i32, -1), getSign(-5.0));
    try std.testing.expectEqual(@as(i32, 0), getSign(0.0));
    try std.testing.expectEqual(@as(i32, 0), getSign(std.math.nan(f64)));
}

test "start and stop check" {
    startCheck();
    const state = getState();
    try std.testing.expect(state.enabled);

    state.raise(.overflow);
    const raised = stopCheck();
    try std.testing.expectEqual(@as(u8, FPException.overflow.toMask()), raised);
    try std.testing.expect(!state.enabled);
}
