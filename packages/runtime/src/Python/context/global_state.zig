/// Global Context Stack and Context Watchers
/// Manages thread-local context state and event notification

const std = @import("std");
const Allocator = std.mem.Allocator;

// Forward declarations
pub const Context = @import("context_impl.zig").Context;

/// Maximum number of context watchers
pub const CONTEXT_MAX_WATCHERS: usize = 8;

/// Context event types for watchers
pub const ContextEvent = enum {
    switched, // Context was switched
};

/// Context watcher callback type
pub const WatchCallback = *const fn (ContextEvent, ?*Context) i32;

// ============================================================================
// Global Context Stack
// ============================================================================

/// Thread-local current context
threadlocal var current_context: ?*Context = null;

/// Get current context
pub fn getCurrentContext() ?*Context {
    return current_context;
}

/// Set current context (internal use by Context.enter/exit)
pub fn setCurrentContext(ctx: ?*Context) void {
    current_context = ctx;
}

/// Copy current context
pub fn copyCurrent(allocator: Allocator) !*Context {
    if (current_context) |ctx| {
        return Context.copy(allocator, ctx);
    }
    return Context.create(allocator);
}

// ============================================================================
// Context Watchers
// ============================================================================

var context_watchers: [CONTEXT_MAX_WATCHERS]?WatchCallback = [_]?WatchCallback{null} ** CONTEXT_MAX_WATCHERS;
var active_watchers: u8 = 0;

/// Add a context watcher
pub fn addWatcher(callback: WatchCallback) !i32 {
    for (&context_watchers, 0..) |*watcher, i| {
        if (watcher.* == null) {
            watcher.* = callback;
            active_watchers |= @as(u8, 1) << @truncate(i);
            return @intCast(i);
        }
    }
    return error.TooManyWatchers;
}

/// Remove a context watcher
pub fn clearWatcher(watcher_id: i32) !void {
    if (watcher_id < 0 or watcher_id >= CONTEXT_MAX_WATCHERS) {
        return error.InvalidWatcherId;
    }

    const idx: usize = @intCast(watcher_id);
    if (context_watchers[idx] == null) {
        return error.WatcherNotSet;
    }

    context_watchers[idx] = null;
    active_watchers &= ~(@as(u8, 1) << @truncate(idx));
}

/// Notify watchers of context event
pub fn notifyWatchers(event: ContextEvent, ctx: ?*Context) void {
    var bits = active_watchers;
    var i: usize = 0;
    while (bits != 0) : (i += 1) {
        if (bits & 1 != 0) {
            if (context_watchers[i]) |callback| {
                _ = callback(event, ctx);
            }
        }
        bits >>= 1;
    }
}
