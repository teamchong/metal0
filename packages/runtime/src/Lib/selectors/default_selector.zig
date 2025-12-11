//! Default selector selection based on platform.

const std = @import("std");
const epoll = @import("epoll_selector.zig");
const kqueue = @import("kqueue_selector.zig");
const poll = @import("poll_selector.zig");

// ============================================================================
// Default Selector
// ============================================================================

/// Default selector for the current platform
pub const DefaultSelector = switch (@import("builtin").os.tag) {
    .linux => epoll.EpollSelector,
    .macos, .freebsd, .netbsd, .openbsd => kqueue.KqueueSelector,
    else => poll.PollSelector,
};

// ============================================================================
// Module Functions
// ============================================================================

/// Create a new selector (platform default)
pub fn createSelector(allocator: std.mem.Allocator) !DefaultSelector {
    return DefaultSelector.init(allocator);
}
