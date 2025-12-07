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
const hamt = @import("hamt.zig");

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of context watchers
pub const CONTEXT_MAX_WATCHERS: usize = 8;

// ============================================================================
// Context Events
// ============================================================================

/// Context event types for watchers
pub const ContextEvent = enum {
    switched, // Context was switched
};

/// Context watcher callback type
pub const WatchCallback = *const fn (ContextEvent, ?*Context) i32;

// ============================================================================
// Token
// ============================================================================

/// Token returned when setting a ContextVar
/// Used to reset the variable to its previous state
pub const Token = struct {
    allocator: Allocator,
    context: *Context,
    var_ref: *ContextVar,
    old_value: ?*anyopaque,
    used: bool = false,

    const Self = @This();
    const MISSING: *anyopaque = @ptrFromInt(1);

    pub fn create(allocator: Allocator, ctx: *Context, var_ref: *ContextVar, old_val: ?*anyopaque) !*Self {
        const token = try allocator.create(Self);
        token.* = .{
            .allocator = allocator,
            .context = ctx,
            .var_ref = var_ref,
            .old_value = old_val,
        };
        return token;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Check if token has been used
    pub fn isUsed(self: *Self) bool {
        return self.used;
    }

    /// Get the associated ContextVar
    pub fn getVar(self: *Self) *ContextVar {
        return self.var_ref;
    }

    /// Get the old value (or null if was missing)
    pub fn getOldValue(self: *Self) ?*anyopaque {
        if (self.old_value == MISSING) return null;
        return self.old_value;
    }
};

// ============================================================================
// ContextVar
// ============================================================================

/// Context Variable - a variable that can have different values in different contexts
pub const ContextVar = struct {
    allocator: Allocator,
    name: []const u8,
    default_value: ?*anyopaque = null,
    has_default: bool = false,

    // Cached value for fast access in current context
    cached_value: ?*anyopaque = null,
    cached_context: ?*Context = null,

    const Self = @This();

    pub fn create(allocator: Allocator, name: []const u8, default: ?*anyopaque) !*Self {
        const cv = try allocator.create(Self);
        cv.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .default_value = default,
            .has_default = default != null,
        };
        return cv;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// Get value in current context
    pub fn get(self: *Self) !?*anyopaque {
        const ctx = getCurrentContext() orelse return self.default_value;

        // Check cache
        if (self.cached_context == ctx) {
            return self.cached_value orelse self.default_value;
        }

        // Lookup in context
        if (ctx.getVar(self)) |value| {
            self.cached_value = value;
            self.cached_context = ctx;
            return value;
        }

        return self.default_value;
    }

    /// Set value in current context, return token for reset
    pub fn set(self: *Self, value: *anyopaque) !*Token {
        const ctx = getCurrentContext() orelse return error.NoContext;

        // Get old value for token
        const old_value = ctx.getVar(self) orelse Token.MISSING;

        // Create token before modifying context
        const token = try Token.create(self.allocator, ctx, self, old_value);

        // Set in context
        try ctx.setVar(self, value);

        // Update cache
        self.cached_value = value;
        self.cached_context = ctx;

        return token;
    }

    /// Reset to value from token
    pub fn reset(self: *Self, token: *Token) !void {
        if (token.used) {
            return error.TokenAlreadyUsed;
        }

        if (token.var_ref != self) {
            return error.WrongToken;
        }

        const ctx = getCurrentContext() orelse return error.NoContext;

        if (token.context != ctx) {
            return error.WrongContext;
        }

        // Reset value
        if (token.old_value == Token.MISSING) {
            try ctx.delVar(self);
        } else {
            try ctx.setVar(self, token.old_value.?);
        }

        // Invalidate cache
        self.cached_value = null;
        self.cached_context = null;

        token.used = true;
    }

    /// Get name
    pub fn getName(self: *Self) []const u8 {
        return self.name;
    }
};

// ============================================================================
// Context
// ============================================================================

/// Context - immutable mapping of ContextVars to values
/// Uses HAMT for efficient structural sharing
pub const Context = struct {
    allocator: Allocator,
    vars: VarMap, // ContextVar -> value mapping
    prev_context: ?*Context = null, // For context stack
    entered: bool = false,

    const Self = @This();

    // Use pointer-based HAMT for context variables
    const VarMap = hamt.Hamt(*ContextVar, *anyopaque);

    fn varHash(cv: *ContextVar) u32 {
        return @truncate(@intFromPtr(cv));
    }

    fn varEql(a: *ContextVar, b: *ContextVar) bool {
        return a == b;
    }

    /// Create empty context
    pub fn create(allocator: Allocator) !*Self {
        const ctx = try allocator.create(Self);
        ctx.* = .{
            .allocator = allocator,
            .vars = VarMap.init(allocator, varHash, varEql),
        };
        return ctx;
    }

    /// Create context as copy of another
    pub fn copy(allocator: Allocator, other: *Self) !*Self {
        const ctx = try allocator.create(Self);
        ctx.* = .{
            .allocator = allocator,
            .vars = other.vars, // Structural sharing via HAMT
        };
        return ctx;
    }

    pub fn destroy(self: *Self) void {
        self.vars.deinit();
        self.allocator.destroy(self);
    }

    /// Get value for a ContextVar
    pub fn getVar(self: *Self, cv: *ContextVar) ?*anyopaque {
        return self.vars.get(cv);
    }

    /// Set value for a ContextVar (creates new context state)
    pub fn setVar(self: *Self, cv: *ContextVar, value: *anyopaque) !void {
        self.vars = try self.vars.set(cv, value);
    }

    /// Delete a ContextVar from context
    pub fn delVar(self: *Self, cv: *ContextVar) !void {
        // HAMT doesn't have delete, so we need to rebuild without this key
        // For now, just set to a sentinel value
        // A proper implementation would add delete to HAMT
        _ = cv;
        // TODO: implement delete in HAMT
    }

    /// Enter this context (push onto stack)
    pub fn enter(self: *Self) !void {
        if (self.entered) {
            return error.ContextAlreadyEntered;
        }

        self.prev_context = current_context;
        current_context = self;
        self.entered = true;

        notifyWatchers(.switched, self);
    }

    /// Exit this context (pop from stack)
    pub fn exit(self: *Self) !void {
        if (!self.entered) {
            return error.ContextNotEntered;
        }

        if (current_context != self) {
            return error.WrongContext;
        }

        current_context = self.prev_context;
        self.prev_context = null;
        self.entered = false;

        notifyWatchers(.switched, current_context);
    }

    /// Run a function in this context
    pub fn run(self: *Self, comptime func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        try self.enter();
        defer self.exit() catch {};

        return @call(.auto, func, args);
    }

    /// Get number of variables in context
    pub fn size(self: *Self) usize {
        return self.vars.size();
    }

    /// Check if context has been entered
    pub fn isEntered(self: *Self) bool {
        return self.entered;
    }

    /// Create iterator over context variables
    pub fn iterator(self: *Self) VarMap.Iterator {
        return self.vars.iterator();
    }
};

// ============================================================================
// Global Context Stack
// ============================================================================

/// Thread-local current context
threadlocal var current_context: ?*Context = null;

/// Get current context
pub fn getCurrentContext() ?*Context {
    return current_context;
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
fn notifyWatchers(event: ContextEvent, ctx: ?*Context) void {
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

test "context var basic" {
    const allocator = std.testing.allocator;

    // Create context and enter it
    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try ctx.enter();
    defer ctx.exit() catch {};

    // Create context var
    const cv = try ContextVar.create(allocator, "test_var", null);
    defer cv.destroy();

    // Initially no value
    const val1 = try cv.get();
    try std.testing.expect(val1 == null);
}

test "context var with default" {
    const allocator = std.testing.allocator;

    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try ctx.enter();
    defer ctx.exit() catch {};

    var default_val: i32 = 42;
    const cv = try ContextVar.create(allocator, "with_default", @ptrCast(&default_val));
    defer cv.destroy();

    const val = try cv.get();
    try std.testing.expect(val != null);
    const int_ptr: *i32 = @ptrCast(@alignCast(val.?));
    try std.testing.expectEqual(@as(i32, 42), int_ptr.*);
}

test "context enter/exit" {
    const allocator = std.testing.allocator;

    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try std.testing.expect(!ctx.isEntered());

    try ctx.enter();
    try std.testing.expect(ctx.isEntered());
    try std.testing.expect(getCurrentContext() == ctx);

    try ctx.exit();
    try std.testing.expect(!ctx.isEntered());
    try std.testing.expect(getCurrentContext() == null);
}

test "context nested" {
    const allocator = std.testing.allocator;

    const ctx1 = try Context.create(allocator);
    defer ctx1.destroy();

    const ctx2 = try Context.create(allocator);
    defer ctx2.destroy();

    try ctx1.enter();
    try std.testing.expect(getCurrentContext() == ctx1);

    try ctx2.enter();
    try std.testing.expect(getCurrentContext() == ctx2);

    try ctx2.exit();
    try std.testing.expect(getCurrentContext() == ctx1);

    try ctx1.exit();
    try std.testing.expect(getCurrentContext() == null);
}

test "context copy" {
    const allocator = std.testing.allocator;

    const ctx1 = try Context.create(allocator);
    defer ctx1.destroy();

    const ctx2 = try Context.copy(allocator, ctx1);
    defer ctx2.destroy();

    // Both should work independently
    try std.testing.expect(!ctx1.isEntered());
    try std.testing.expect(!ctx2.isEntered());
}

test "context watcher" {
    var watcher_called = false;

    const callback = struct {
        fn cb(_: ContextEvent, _: ?*Context) i32 {
            // Can't modify outer scope easily, but test compiles
            return 0;
        }
    }.cb;

    const watcher_id = try addWatcher(callback);
    try std.testing.expect(watcher_id >= 0);

    try clearWatcher(watcher_id);

    _ = watcher_called;
}
