/// context - Context Variables
/// Mirrors cpython/Python/context.c
///
/// This module provides context variables (PEP 567) for Python:
/// - Context: immutable mapping of ContextVars to values
/// - ContextVar: individual context variable with default value
/// - Token: represents a state for resetting a ContextVar
/// - Uses HAMT for efficient copy-on-write semantics

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of context watchers
pub const CONTEXT_MAX_WATCHERS: usize = 8;

// ============================================================================
// Core Types
// ============================================================================

pub const Token = @import("context/token.zig").Token;
pub const ContextVar = @import("context/context_var.zig").ContextVar;
pub const Context = @import("context/context_impl.zig").Context;

// ============================================================================
// Context Events
// ============================================================================

const global_state = @import("context/global_state.zig");

/// Context event types for watchers
pub const ContextEvent = global_state.ContextEvent;

/// Context watcher callback type
pub const WatchCallback = global_state.WatchCallback;

// ============================================================================
// Global Context Stack
// ============================================================================

/// Get current context
pub fn getCurrentContext() ?*Context {
    return global_state.getCurrentContext();
}

/// Copy current context
pub fn copyCurrent(allocator: Allocator) !*Context {
    return global_state.copyCurrent(allocator);
}

// ============================================================================
// Context Watchers
// ============================================================================

/// Add a context watcher
pub fn addWatcher(callback: WatchCallback) !i32 {
    return global_state.addWatcher(callback);
}

/// Remove a context watcher
pub fn clearWatcher(watcher_id: i32) !void {
    return global_state.clearWatcher(watcher_id);
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a new empty context
pub fn createContext(allocator: Allocator) !*Context {
    return Context.create(allocator);
}

/// Create a new context variable
pub fn createVar(allocator: Allocator, name: []const u8, default: ?*anyopaque) !*ContextVar {
    return ContextVar.create(allocator, name, default);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("context/tests.zig");
}
