//! asyncio.mixins - Mixin classes for asyncio
//! Reference: cpython/Lib/asyncio/mixins.py

const std = @import("std");
const events = @import("events.zig");

/// Loop bound mixin - binds object to specific event loop
/// CPython: class _LoopBoundMixin
pub const LoopBoundMixin = struct {
    loop: ?*events.AbstractEventLoop,

    pub fn init() LoopBoundMixin {
        return .{
            .loop = null,
        };
    }

    /// Get the event loop bound to this object
    pub fn getLoop(self: *LoopBoundMixin) ?*events.AbstractEventLoop {
        return self.loop;
    }

    /// Bind to a specific event loop
    pub fn bindLoop(self: *LoopBoundMixin, loop: *events.AbstractEventLoop) void {
        self.loop = loop;
    }
};

/// Context manager mixin for async with support
/// CPython: class _ContextManagerMixin
pub const ContextManagerMixin = struct {
    entered: bool,

    pub fn init() ContextManagerMixin {
        return .{
            .entered = false,
        };
    }

    /// Enter context (__aenter__)
    pub fn enter(self: *ContextManagerMixin) !void {
        if (self.entered) {
            return error.AlreadyEntered;
        }
        self.entered = true;
    }

    /// Exit context (__aexit__)
    pub fn exit(self: *ContextManagerMixin) void {
        self.entered = false;
    }
};

// Tests
test "LoopBoundMixin" {
    var mixin = LoopBoundMixin.init();
    try std.testing.expect(mixin.getLoop() == null);
}

test "ContextManagerMixin" {
    var mixin = ContextManagerMixin.init();
    try std.testing.expect(!mixin.entered);

    try mixin.enter();
    try std.testing.expect(mixin.entered);

    mixin.exit();
    try std.testing.expect(!mixin.entered);
}
