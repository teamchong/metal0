/// Timeout Handling
/// Deadline tracking and timeout management for blocking operations

const constants = @import("constants.zig");
const conversion = @import("conversion.zig");
const clocks = @import("clocks.zig");

/// Deadline for timeout operations
pub const Deadline = struct {
    start: i64,
    timeout_ns: i64,

    const Self = @This();

    /// Create a deadline from timeout in seconds
    pub fn fromSeconds(timeout: f64) !Self {
        const timeout_ns = try conversion.secondsToNanos(timeout);
        return .{
            .start = clocks.monotonicNanos(),
            .timeout_ns = timeout_ns,
        };
    }

    /// Create a deadline from timeout in nanoseconds
    pub fn fromNanos(timeout_ns: i64) Self {
        return .{
            .start = clocks.monotonicNanos(),
            .timeout_ns = timeout_ns,
        };
    }

    /// Check if deadline has passed
    pub fn isExpired(self: Self) bool {
        if (self.timeout_ns < 0) return false; // Infinite timeout
        const elapsed = clocks.monotonicNanos() - self.start;
        return elapsed >= self.timeout_ns;
    }

    /// Get remaining time in nanoseconds
    pub fn remainingNanos(self: Self) i64 {
        if (self.timeout_ns < 0) return constants.TIME_MAX; // Infinite
        const elapsed = clocks.monotonicNanos() - self.start;
        const remaining = self.timeout_ns - elapsed;
        return if (remaining < 0) 0 else remaining;
    }

    /// Get remaining time in seconds
    pub fn remainingSeconds(self: Self) f64 {
        return conversion.nanosToSeconds(self.remainingNanos());
    }

    /// Update timeout to remaining time (for restarting interrupted operations)
    pub fn updateRemaining(self: *Self) void {
        const remaining = self.remainingNanos();
        self.timeout_ns = remaining;
        self.start = clocks.monotonicNanos();
    }
};
