//! Finalizer registry for weak references
//!
//! Provides simulated finalizer support.

// ============================================================================
// Finalize - Add finalizer to object (simulated)
// ============================================================================

/// Simulated finalizer registry
pub const Finalizer = struct {
    const Self = @This();

    callback: *const fn (*anyopaque) void,
    data: *anyopaque,

    pub fn init(comptime T: type, obj: *T, callback: *const fn (*T) void) Self {
        return .{
            .callback = @ptrCast(callback),
            .data = @ptrCast(obj),
        };
    }

    pub fn run(self: Self) void {
        self.callback(self.data);
    }
};
