/// emscripten_signal - Emscripten Signal Handling
/// Mirrors cpython/Python/emscripten_signal.c
///
/// Signal handling for WebAssembly/Emscripten builds.
/// Provides limited signal support in browser environment.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Emscripten/WASM
pub const is_emscripten = builtin.os.tag == .emscripten or builtin.cpu.arch == .wasm32;

// ============================================================================
// Signal Numbers
// ============================================================================

/// Emscripten-supported signals (subset of POSIX)
pub const Signal = enum(i32) {
    SIGHUP = 1,
    SIGINT = 2,
    SIGQUIT = 3,
    SIGILL = 4,
    SIGTRAP = 5,
    SIGABRT = 6,
    SIGBUS = 7,
    SIGFPE = 8,
    SIGKILL = 9,
    SIGUSR1 = 10,
    SIGSEGV = 11,
    SIGUSR2 = 12,
    SIGPIPE = 13,
    SIGALRM = 14,
    SIGTERM = 15,
    SIGCHLD = 17,
    SIGCONT = 18,
    SIGSTOP = 19,
    SIGTSTP = 20,
    SIGTTIN = 21,
    SIGTTOU = 22,
    SIGURG = 23,
    SIGXCPU = 24,
    SIGXFSZ = 25,
    SIGVTALRM = 26,
    SIGPROF = 27,
    SIGWINCH = 28,
    SIGIO = 29,
    SIGPWR = 30,
    SIGSYS = 31,
};

/// Signal handler function type
pub const SignalHandler = *const fn (i32) void;

/// Special signal handler values
pub const SIG_DFL: ?SignalHandler = null;
pub const SIG_IGN: ?SignalHandler = @ptrFromInt(1);

// ============================================================================
// Signal State
// ============================================================================

/// Signal handler state
pub const SignalState = struct {
    const Self = @This();

    /// Registered handlers
    handlers: [32]?SignalHandler = [_]?SignalHandler{null} ** 32,
    /// Pending signals (bit mask)
    pending: u32 = 0,
    /// Blocked signals (bit mask)
    blocked: u32 = 0,
    /// Signal handler lock
    mutex: std.Thread.Mutex = .{},

    /// Set a signal handler
    pub fn setHandler(self: *Self, sig: Signal, handler: ?SignalHandler) ?SignalHandler {
        self.mutex.lock();
        defer self.mutex.unlock();

        const idx = @as(usize, @intCast(@intFromEnum(sig)));
        if (idx >= 32) return null;

        const old = self.handlers[idx];
        self.handlers[idx] = handler;
        return old;
    }

    /// Get current handler
    pub fn getHandler(self: *Self, sig: Signal) ?SignalHandler {
        self.mutex.lock();
        defer self.mutex.unlock();

        const idx = @as(usize, @intCast(@intFromEnum(sig)));
        if (idx >= 32) return null;
        return self.handlers[idx];
    }

    /// Raise a signal
    pub fn raise(self: *Self, sig: Signal) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const idx = @as(usize, @intCast(@intFromEnum(sig)));
        if (idx >= 32) return;

        // Check if blocked
        if ((self.blocked & (@as(u32, 1) << @intCast(idx))) != 0) {
            // Mark as pending
            self.pending |= (@as(u32, 1) << @intCast(idx));
            return;
        }

        // Call handler if set
        if (self.handlers[idx]) |handler| {
            if (handler != SIG_IGN) {
                handler(@intFromEnum(sig));
            }
        }
    }

    /// Block signals
    pub fn block(self: *Self, mask: u32) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const old = self.blocked;
        self.blocked |= mask;
        return old;
    }

    /// Unblock signals
    pub fn unblock(self: *Self, mask: u32) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const old = self.blocked;
        self.blocked &= ~mask;

        // Deliver pending signals that are now unblocked
        const deliverable = self.pending & ~self.blocked;
        if (deliverable != 0) {
            self.deliverPending(deliverable);
        }

        return old;
    }

    /// Deliver pending signals
    fn deliverPending(self: *Self, mask: u32) void {
        var sig_mask = mask;
        var idx: usize = 0;
        while (sig_mask != 0) : (idx += 1) {
            if ((sig_mask & 1) != 0) {
                self.pending &= ~(@as(u32, 1) << @intCast(idx));
                if (self.handlers[idx]) |handler| {
                    if (handler != SIG_IGN) {
                        handler(@intCast(idx));
                    }
                }
            }
            sig_mask >>= 1;
        }
    }

    /// Check if signal is pending
    pub fn isPending(self: *Self, sig: Signal) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const idx = @as(usize, @intCast(@intFromEnum(sig)));
        if (idx >= 32) return false;
        return (self.pending & (@as(u32, 1) << @intCast(idx))) != 0;
    }
};

// ============================================================================
// Keyboard Interrupt Handling
// ============================================================================

/// Keyboard interrupt state
pub const KeyboardInterruptState = struct {
    /// Interrupt was triggered
    triggered: bool = false,
    /// Interrupt is enabled
    enabled: bool = true,

    /// Check and clear interrupt flag
    pub fn check(self: *@This()) bool {
        if (self.triggered) {
            self.triggered = false;
            return true;
        }
        return false;
    }

    /// Trigger keyboard interrupt
    pub fn trigger(self: *@This()) void {
        if (self.enabled) {
            self.triggered = true;
        }
    }

    /// Enable/disable interrupts
    pub fn setEnabled(self: *@This(), enabled: bool) void {
        self.enabled = enabled;
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var signal_state: SignalState = .{};
var keyboard_interrupt: KeyboardInterruptState = .{};

/// Initialize the emscripten_signal module
pub fn init() void {
    if (initialized) return;
    initialized = true;

    // Set up default handlers for critical signals
    if (is_emscripten) {
        // In Emscripten, we need to register with the JS event loop
        setupEmscriptenSignals();
    }
}

/// Set up Emscripten-specific signal handling
fn setupEmscriptenSignals() void {
    // Would call emscripten_set_main_loop_callback or similar
}

/// Reset module state
pub fn reset() void {
    signal_state = .{};
    keyboard_interrupt = .{};
    initialized = false;
}

// ============================================================================
// Public API
// ============================================================================

/// Install a signal handler
pub fn signal(sig: Signal, handler: ?SignalHandler) ?SignalHandler {
    return signal_state.setHandler(sig, handler);
}

/// Raise a signal
pub fn raise(sig: Signal) void {
    signal_state.raise(sig);
}

/// Check for keyboard interrupt
pub fn checkInterrupt() bool {
    return keyboard_interrupt.check();
}

/// Trigger keyboard interrupt (called from JS)
pub fn triggerInterrupt() void {
    keyboard_interrupt.trigger();
    signal_state.raise(.SIGINT);
}

/// Block signals
pub fn sigBlock(mask: u32) u32 {
    return signal_state.block(mask);
}

/// Unblock signals
pub fn sigUnblock(mask: u32) u32 {
    return signal_state.unblock(mask);
}

/// Create signal mask from signals
pub fn sigMask(signals: []const Signal) u32 {
    var mask: u32 = 0;
    for (signals) |sig| {
        mask |= (@as(u32, 1) << @intCast(@intFromEnum(sig)));
    }
    return mask;
}

// ============================================================================
// Tests
// ============================================================================

test "signal enum" {
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(Signal.SIGINT));
    try std.testing.expectEqual(@as(i32, 15), @intFromEnum(Signal.SIGTERM));
}

test "signal state" {
    var state = SignalState{};

    // Test handler set/get
    const old = state.setHandler(.SIGINT, null);
    try std.testing.expect(old == null);

    const current = state.getHandler(.SIGINT);
    try std.testing.expect(current == null);
}

test "keyboard interrupt" {
    var ki = KeyboardInterruptState{};

    try std.testing.expect(!ki.check());

    ki.trigger();
    try std.testing.expect(ki.check());
    try std.testing.expect(!ki.check()); // Cleared after check
}

test "signal mask" {
    const mask = sigMask(&[_]Signal{ .SIGINT, .SIGTERM });
    try std.testing.expect((mask & (@as(u32, 1) << 2)) != 0); // SIGINT
    try std.testing.expect((mask & (@as(u32, 1) << 15)) != 0); // SIGTERM
}

test "block unblock" {
    var state = SignalState{};

    const old = state.block(sigMask(&[_]Signal{.SIGINT}));
    try std.testing.expectEqual(@as(u32, 0), old);

    state.raise(.SIGINT);
    try std.testing.expect(state.isPending(.SIGINT));
}
