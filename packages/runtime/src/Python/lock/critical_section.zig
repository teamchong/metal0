/// critical_section - Critical Section Implementation
/// Protects code regions with nested lock management

const pymutex = @import("pymutex.zig");

// ============================================================================
// Critical Section
// ============================================================================

/// Critical section for protecting code regions
pub const CriticalSection = struct {
    mutex: pymutex.PyMutex = .{},
    prev: ?*CriticalSection = null,

    const Self = @This();

    /// Begin critical section
    pub fn begin(self: *Self, prev: ?*CriticalSection) void {
        self.prev = prev;
        self.mutex.lock();
    }

    /// End critical section
    pub fn end(self: *Self) ?*CriticalSection {
        const prev = self.prev;
        self.mutex.unlock();
        return prev;
    }
};
