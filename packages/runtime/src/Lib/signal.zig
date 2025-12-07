//! CPython source: Lib/signal.py
//!
//! Provides mechanisms to set handlers for asynchronous events.
//!
//! Mirrors: CPython Lib/signal.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Signal Numbers
// ============================================================================

/// Signal numbers (POSIX)
pub const Signal = enum(i32) {
    SIGHUP = 1, // Hangup
    SIGINT = 2, // Interrupt (Ctrl+C)
    SIGQUIT = 3, // Quit
    SIGILL = 4, // Illegal instruction
    SIGTRAP = 5, // Trace trap
    SIGABRT = 6, // Abort
    SIGBUS = 7, // Bus error
    SIGFPE = 8, // Floating point exception
    SIGKILL = 9, // Kill (cannot be caught)
    SIGUSR1 = 10, // User-defined signal 1
    SIGSEGV = 11, // Segmentation fault
    SIGUSR2 = 12, // User-defined signal 2
    SIGPIPE = 13, // Broken pipe
    SIGALRM = 14, // Alarm clock
    SIGTERM = 15, // Termination
    SIGSTKFLT = 16, // Stack fault
    SIGCHLD = 17, // Child status changed
    SIGCONT = 18, // Continue
    SIGSTOP = 19, // Stop (cannot be caught)
    SIGTSTP = 20, // Terminal stop
    SIGTTIN = 21, // Background read from tty
    SIGTTOU = 22, // Background write to tty
    SIGURG = 23, // Urgent data on socket
    SIGXCPU = 24, // CPU time limit exceeded
    SIGXFSZ = 25, // File size limit exceeded
    SIGVTALRM = 26, // Virtual timer expired
    SIGPROF = 27, // Profiling timer expired
    SIGWINCH = 28, // Window size changed
    SIGIO = 29, // I/O possible
    SIGPWR = 30, // Power failure
    SIGSYS = 31, // Bad system call

    pub fn name(self: Signal) []const u8 {
        return @tagName(self);
    }

    pub fn toInt(self: Signal) i32 {
        return @intFromEnum(self);
    }

    pub fn fromInt(val: i32) ?Signal {
        if (val >= 1 and val <= 31) {
            return @enumFromInt(val);
        }
        return null;
    }
};

// Convenience aliases
pub const SIGHUP = Signal.SIGHUP;
pub const SIGINT = Signal.SIGINT;
pub const SIGQUIT = Signal.SIGQUIT;
pub const SIGILL = Signal.SIGILL;
pub const SIGTRAP = Signal.SIGTRAP;
pub const SIGABRT = Signal.SIGABRT;
pub const SIGBUS = Signal.SIGBUS;
pub const SIGFPE = Signal.SIGFPE;
pub const SIGKILL = Signal.SIGKILL;
pub const SIGUSR1 = Signal.SIGUSR1;
pub const SIGSEGV = Signal.SIGSEGV;
pub const SIGUSR2 = Signal.SIGUSR2;
pub const SIGPIPE = Signal.SIGPIPE;
pub const SIGALRM = Signal.SIGALRM;
pub const SIGTERM = Signal.SIGTERM;
pub const SIGCHLD = Signal.SIGCHLD;
pub const SIGCONT = Signal.SIGCONT;
pub const SIGSTOP = Signal.SIGSTOP;
pub const SIGTSTP = Signal.SIGTSTP;
pub const SIGTTIN = Signal.SIGTTIN;
pub const SIGTTOU = Signal.SIGTTOU;
pub const SIGURG = Signal.SIGURG;
pub const SIGXCPU = Signal.SIGXCPU;
pub const SIGXFSZ = Signal.SIGXFSZ;
pub const SIGVTALRM = Signal.SIGVTALRM;
pub const SIGPROF = Signal.SIGPROF;
pub const SIGWINCH = Signal.SIGWINCH;
pub const SIGIO = Signal.SIGIO;
pub const SIGPWR = Signal.SIGPWR;
pub const SIGSYS = Signal.SIGSYS;

// ============================================================================
// Special Handler Values
// ============================================================================

/// Default signal handler
pub const SIG_DFL: i32 = 0;

/// Ignore signal
pub const SIG_IGN: i32 = 1;

// ============================================================================
// Signal Handler Type
// ============================================================================

/// Signal handler function type
pub const SignalHandler = *const fn (sig: i32) void;

/// Signal handler union (can be function or special value)
pub const Handler = union(enum) {
    default,
    ignore,
    function: SignalHandler,

    pub fn fromInt(val: i32) Handler {
        return switch (val) {
            SIG_DFL => .default,
            SIG_IGN => .ignore,
            else => .default,
        };
    }
};

// ============================================================================
// Signal State
// ============================================================================

var handlers: [32]Handler = [_]Handler{.default} ** 32;
var pending_signals: u32 = 0;

// ============================================================================
// Signal Functions
// ============================================================================

/// Set a signal handler
pub fn setSignal(sig: Signal, handler: Handler) Handler {
    const idx = @as(usize, @intCast(@intFromEnum(sig)));
    const old_handler = handlers[idx];
    handlers[idx] = handler;

    // On POSIX systems, would actually set the signal handler
    // std.os.sigaction(...)

    return old_handler;
}

/// Get the current signal handler
pub fn getSignal(sig: Signal) Handler {
    const idx = @as(usize, @intCast(@intFromEnum(sig)));
    return handlers[idx];
}

/// Raise a signal (send to current process)
pub fn raise(sig: Signal) !void {
    const idx = @as(usize, @intCast(@intFromEnum(sig)));

    switch (handlers[idx]) {
        .default => {
            // Would perform default action
            // For now, just set pending
            pending_signals |= @as(u32, 1) << @as(u5, @intCast(@intFromEnum(sig)));
        },
        .ignore => {
            // Do nothing
        },
        .function => |handler| {
            handler(@intFromEnum(sig));
        },
    }
}

/// Check if a signal is pending
pub fn pending() u32 {
    return pending_signals;
}

/// Clear pending signals
pub fn clearPending() void {
    pending_signals = 0;
}

// ============================================================================
// Alarm Functions
// ============================================================================

var alarm_time: ?i64 = null;

/// Set an alarm to send SIGALRM after `seconds`
pub fn alarm(seconds: u32) u32 {
    const old_remaining: u32 = if (alarm_time) |t| blk: {
        const now = std.time.timestamp();
        if (t > now) {
            break :blk @intCast(t - now);
        }
        break :blk 0;
    } else 0;

    if (seconds == 0) {
        alarm_time = null;
    } else {
        alarm_time = std.time.timestamp() + seconds;
    }

    return old_remaining;
}

/// Schedule SIGALRM after `seconds` (with subsecond precision)
pub fn setitimer(seconds: f64) void {
    if (seconds <= 0) {
        alarm_time = null;
    } else {
        alarm_time = std.time.timestamp() + @as(i64, @intFromFloat(seconds));
    }
}

/// Get time remaining on alarm
pub fn getitimer() f64 {
    if (alarm_time) |t| {
        const now = std.time.timestamp();
        if (t > now) {
            return @floatFromInt(t - now);
        }
    }
    return 0.0;
}

// ============================================================================
// Signal Sets
// ============================================================================

/// Signal set (bitmask of signals)
pub const Sigset = struct {
    bits: u32 = 0,

    pub fn init() Sigset {
        return .{ .bits = 0 };
    }

    /// Add a signal to the set
    pub fn add(self: *Sigset, sig: Signal) void {
        self.bits |= @as(u32, 1) << @as(u5, @intCast(@intFromEnum(sig)));
    }

    /// Remove a signal from the set
    pub fn remove(self: *Sigset, sig: Signal) void {
        self.bits &= ~(@as(u32, 1) << @as(u5, @intCast(@intFromEnum(sig))));
    }

    /// Check if signal is in set
    pub fn contains(self: *const Sigset, sig: Signal) bool {
        return (self.bits & (@as(u32, 1) << @as(u5, @intCast(@intFromEnum(sig))))) != 0;
    }

    /// Fill set with all signals
    pub fn fill(self: *Sigset) void {
        self.bits = 0xFFFFFFFF;
    }

    /// Empty the set
    pub fn empty(self: *Sigset) void {
        self.bits = 0;
    }

    /// Check if set is empty
    pub fn isEmpty(self: *const Sigset) bool {
        return self.bits == 0;
    }
};

// ============================================================================
// Signal Blocking
// ============================================================================

var blocked_signals = Sigset.init();

/// Block signals in the given set
pub fn pthread_sigmask(how: enum { block, unblock, setmask }, set: Sigset) Sigset {
    const old = blocked_signals;

    switch (how) {
        .block => blocked_signals.bits |= set.bits,
        .unblock => blocked_signals.bits &= ~set.bits,
        .setmask => blocked_signals.bits = set.bits,
    }

    return old;
}

/// Get the current signal mask
pub fn sigpending_mask() Sigset {
    return blocked_signals;
}

// ============================================================================
// Interval Timer
// ============================================================================

/// Interval timer types
pub const ITimer = enum(i32) {
    ITIMER_REAL = 0, // Decrements in real time
    ITIMER_VIRTUAL = 1, // Decrements in process virtual time
    ITIMER_PROF = 2, // Decrements in process time + system time
};

pub const ITIMER_REAL = ITimer.ITIMER_REAL;
pub const ITIMER_VIRTUAL = ITimer.ITIMER_VIRTUAL;
pub const ITIMER_PROF = ITimer.ITIMER_PROF;

/// Interval timer value
pub const ITimerVal = struct {
    interval: f64, // Interval for periodic timer
    value: f64, // Current value (time until next signal)
};

var itimers: [3]ITimerVal = [_]ITimerVal{.{ .interval = 0, .value = 0 }} ** 3;

/// Set an interval timer
pub fn setIntervalTimer(which: ITimer, new_value: ITimerVal) ITimerVal {
    const idx = @intFromEnum(which);
    const old = itimers[idx];
    itimers[idx] = new_value;
    return old;
}

/// Get interval timer value
pub fn getIntervalTimer(which: ITimer) ITimerVal {
    const idx = @intFromEnum(which);
    return itimers[idx];
}

// ============================================================================
// Pause and Wait
// ============================================================================

/// Pause until a signal is received
pub fn pause() void {
    // In real implementation, would use std.os.pause()
    // For now, just a busy wait with sleep
    std.time.sleep(1 * std.time.ns_per_ms);
}

/// Wait for a signal from the given set
pub fn sigwait(set: Sigset) ?Signal {
    // Check pending signals that match the set
    const pending_and_waiting = pending_signals & set.bits;
    if (pending_and_waiting != 0) {
        // Return first matching signal
        var i: u5 = 0;
        while (i < 32) : (i += 1) {
            if ((pending_and_waiting & (@as(u32, 1) << i)) != 0) {
                // Clear the signal
                pending_signals &= ~(@as(u32, 1) << i);
                return @enumFromInt(i);
            }
        }
    }
    return null;
}

// ============================================================================
// Signal Names
// ============================================================================

/// Get a dictionary of signal names
pub fn getSignalNames() [32]?[]const u8 {
    var names: [32]?[]const u8 = [_]?[]const u8{null} ** 32;
    inline for (std.meta.fields(Signal)) |field| {
        names[@intFromEnum(@as(Signal, @enumFromInt(field.value)))] = field.name;
    }
    return names;
}

/// Get signal name
pub fn strsignal(sig: i32) ?[]const u8 {
    if (Signal.fromInt(sig)) |s| {
        return s.name();
    }
    return null;
}

// ============================================================================
// Validation
// ============================================================================

/// Check if signal number is valid
pub fn validSignal(sig: i32) bool {
    return sig >= 1 and sig <= 31;
}

/// Get number of signals
pub fn nsig() i32 {
    return 32;
}

// ============================================================================
// Tests
// ============================================================================

test "Signal enum" {
    try std.testing.expectEqual(@as(i32, 2), Signal.SIGINT.toInt());
    try std.testing.expectEqual(@as(i32, 15), Signal.SIGTERM.toInt());
    try std.testing.expectEqual(Signal.SIGINT, Signal.fromInt(2).?);
}

test "Signal names" {
    try std.testing.expectEqualStrings("SIGINT", Signal.SIGINT.name());
    try std.testing.expectEqualStrings("SIGTERM", Signal.SIGTERM.name());
}

test "Sigset" {
    var set = Sigset.init();
    try std.testing.expect(set.isEmpty());

    set.add(.SIGINT);
    try std.testing.expect(set.contains(.SIGINT));
    try std.testing.expect(!set.contains(.SIGTERM));

    set.add(.SIGTERM);
    try std.testing.expect(set.contains(.SIGTERM));

    set.remove(.SIGINT);
    try std.testing.expect(!set.contains(.SIGINT));
    try std.testing.expect(set.contains(.SIGTERM));

    set.empty();
    try std.testing.expect(set.isEmpty());
}

test "setSignal" {
    const old = setSignal(.SIGINT, .ignore);
    try std.testing.expect(old == .default);

    const current = getSignal(.SIGINT);
    try std.testing.expect(current == .ignore);

    _ = setSignal(.SIGINT, .default);
}

test "alarm" {
    const old = alarm(10);
    try std.testing.expectEqual(@as(u32, 0), old);

    // Cancel alarm
    const remaining = alarm(0);
    try std.testing.expect(remaining <= 10);
}

test "validSignal" {
    try std.testing.expect(validSignal(1));
    try std.testing.expect(validSignal(15));
    try std.testing.expect(validSignal(31));
    try std.testing.expect(!validSignal(0));
    try std.testing.expect(!validSignal(32));
    try std.testing.expect(!validSignal(-1));
}

test "strsignal" {
    try std.testing.expectEqualStrings("SIGINT", strsignal(2).?);
    try std.testing.expect(strsignal(100) == null);
}
