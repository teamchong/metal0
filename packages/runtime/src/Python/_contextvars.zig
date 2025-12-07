/// _contextvars - Context Variables Implementation
/// Mirrors cpython/Python/_contextvars.c
///
/// This module provides the C-level implementation of context variables:
/// - ContextVar object type
/// - Context object type
/// - Token object for reset operations
/// - Copy-on-write context management

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Error Types
// ============================================================================

pub const ContextError = error{
    LookupError,
    ValueError,
    RuntimeError,
    OutOfMemory,
};

// ============================================================================
// Context Variable
// ============================================================================

/// A context variable that can hold different values in different contexts
pub const ContextVar = struct {
    /// Name of the variable
    name: []const u8,
    /// Default value (if any)
    default: ?*anyopaque,
    /// Hash for quick lookup
    hash: u64,
    /// Cached value in current context
    cached_value: ?*anyopaque,
    /// Cached context token
    cached_context: ?*anyopaque,

    const Self = @This();

    /// Create a new context variable
    pub fn init(name: []const u8, default: ?*anyopaque) Self {
        return .{
            .name = name,
            .default = default,
            .hash = hashName(name),
            .cached_value = null,
            .cached_context = null,
        };
    }

    /// Get the value in the current context
    pub fn get(self: *Self, ctx: *Context) ContextError!?*anyopaque {
        // Check cache
        if (self.cached_context == ctx) {
            if (self.cached_value) |v| return v;
        }

        // Lookup in context
        if (ctx.lookup(self.hash)) |value| {
            self.cached_value = value;
            self.cached_context = ctx;
            return value;
        }

        // Return default
        if (self.default) |d| return d;

        return ContextError.LookupError;
    }

    /// Set the value in the current context
    pub fn set(self: *Self, ctx: *Context, value: *anyopaque) !Token {
        const old_value = ctx.lookup(self.hash);

        try ctx.set(self.hash, value);

        // Update cache
        self.cached_value = value;
        self.cached_context = ctx;

        // Return token for reset
        return Token{
            .var_ref = self,
            .old_value = old_value,
            .used = false,
        };
    }

    /// Reset to previous value using token
    pub fn reset(self: *Self, ctx: *Context, token: *Token) !void {
        if (token.used) {
            return ContextError.RuntimeError;
        }
        if (token.var_ref != self) {
            return ContextError.ValueError;
        }

        token.used = true;

        if (token.old_value) |old| {
            try ctx.set(self.hash, old);
            self.cached_value = old;
        } else {
            ctx.remove(self.hash);
            self.cached_value = null;
        }
    }

    fn hashName(name: []const u8) u64 {
        var hash: u64 = 5381;
        for (name) |c| {
            hash = ((hash << 5) +% hash) +% c;
        }
        return hash;
    }
};

// ============================================================================
// Token
// ============================================================================

/// Token for resetting a context variable to its previous value
pub const Token = struct {
    /// The variable this token is for
    var_ref: *ContextVar,
    /// The old value to restore
    old_value: ?*anyopaque,
    /// Whether this token has been used
    used: bool,

    /// Sentinel value for missing
    pub const MISSING: ?*anyopaque = null;
};

// ============================================================================
// Context
// ============================================================================

/// A context holding variable values
pub const Context = struct {
    /// Variable values (hash -> value)
    values: std.AutoHashMap(u64, *anyopaque),
    /// Parent context (for copy-on-write)
    parent: ?*Context,
    /// Whether this context has been modified
    modified: bool,
    /// Reference count
    refcount: u32,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    /// Create a new empty context
    pub fn init(allocator: Allocator) Self {
        return .{
            .values = std.AutoHashMap(u64, *anyopaque).init(allocator),
            .parent = null,
            .modified = false,
            .refcount = 1,
            .allocator = allocator,
        };
    }

    /// Create a copy of another context
    pub fn copy(allocator: Allocator, other: *Self) !Self {
        var ctx = Self.init(allocator);
        ctx.parent = other;
        other.refcount += 1;
        return ctx;
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.values.deinit();
        if (self.parent) |p| {
            p.refcount -= 1;
            if (p.refcount == 0) {
                p.deinit();
                self.allocator.destroy(p);
            }
        }
    }

    /// Lookup a value by hash
    pub fn lookup(self: *Self, hash: u64) ?*anyopaque {
        // Check local values first
        if (self.values.get(hash)) |v| {
            return v;
        }

        // Check parent
        if (self.parent) |p| {
            return p.lookup(hash);
        }

        return null;
    }

    /// Set a value
    pub fn set(self: *Self, hash: u64, value: *anyopaque) !void {
        try self.values.put(hash, value);
        self.modified = true;
    }

    /// Remove a value
    pub fn remove(self: *Self, hash: u64) void {
        _ = self.values.remove(hash);
        self.modified = true;
    }

    /// Get number of local values
    pub fn len(self: *const Self) usize {
        return self.values.count();
    }

    /// Check if context is empty
    pub fn isEmpty(self: *const Self) bool {
        if (self.values.count() > 0) return false;
        if (self.parent) |p| return p.isEmpty();
        return true;
    }

    /// Flatten context (copy all values from parent)
    pub fn flatten(self: *Self) !void {
        if (self.parent) |p| {
            var iter = p.values.iterator();
            while (iter.next()) |entry| {
                if (!self.values.contains(entry.key_ptr.*)) {
                    try self.values.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            p.refcount -= 1;
            if (p.refcount == 0) {
                p.deinit();
                self.allocator.destroy(p);
            }
            self.parent = null;
        }
    }

    /// Iterate over all values
    pub fn iterator(self: *Self) std.AutoHashMap(u64, *anyopaque).Iterator {
        return self.values.iterator();
    }
};

// ============================================================================
// Context Stack
// ============================================================================

/// Stack of contexts for nested context management
pub const ContextStack = struct {
    stack: std.ArrayList(*Context),
    current: ?*Context,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .stack = std.ArrayList(*Context).init(allocator),
            .current = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    /// Enter a new context
    pub fn enter(self: *Self, ctx: *Context) !void {
        if (self.current) |c| {
            try self.stack.append(c);
        }
        self.current = ctx;
    }

    /// Exit current context
    pub fn exit(self: *Self) ?*Context {
        const old = self.current;
        self.current = self.stack.popOrNull();
        return old;
    }

    /// Get current context
    pub fn getCurrent(self: *const Self) ?*Context {
        return self.current;
    }

    /// Get depth
    pub fn depth(self: *const Self) usize {
        return self.stack.items.len + @intFromBool(self.current != null);
    }
};

// ============================================================================
// Thread-Local Context
// ============================================================================

/// Thread-local context storage
threadlocal var tls_context_stack: ?ContextStack = null;

/// Get thread-local context stack
pub fn getContextStack(allocator: Allocator) *ContextStack {
    if (tls_context_stack == null) {
        tls_context_stack = ContextStack.init(allocator);
    }
    return &tls_context_stack.?;
}

/// Get current context for this thread
pub fn getCurrentContext(allocator: Allocator) ?*Context {
    return getContextStack(allocator).getCurrent();
}

// ============================================================================
// Context Manager
// ============================================================================

/// RAII-style context manager
pub const ContextManager = struct {
    stack: *ContextStack,
    ctx: *Context,

    const Self = @This();

    pub fn init(stack: *ContextStack, ctx: *Context) !Self {
        try stack.enter(ctx);
        return .{
            .stack = stack,
            .ctx = ctx,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self.stack.exit();
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "context var basic" {
    var default_val: u32 = 42;
    var cv = ContextVar.init("test_var", &default_val);

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    // Get default
    const val = try cv.get(&ctx);
    try std.testing.expect(val == &default_val);
}

test "context var set and get" {
    var cv = ContextVar.init("test_var", null);

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    var new_val: u32 = 100;
    _ = try cv.set(&ctx, &new_val);

    const val = try cv.get(&ctx);
    try std.testing.expect(val == &new_val);
}

test "context var reset with token" {
    var default_val: u32 = 42;
    var cv = ContextVar.init("test_var", &default_val);

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    var new_val: u32 = 100;
    var token = try cv.set(&ctx, &new_val);

    // Value is new
    const val1 = try cv.get(&ctx);
    try std.testing.expect(val1 == &new_val);

    // Reset
    try cv.reset(&ctx, &token);

    // Value is back to default
    const val2 = try cv.get(&ctx);
    try std.testing.expect(val2 == &default_val);
}

test "context basic" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(ctx.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), ctx.len());

    var val: u32 = 42;
    try ctx.set(12345, &val);

    try std.testing.expect(!ctx.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), ctx.len());

    const found = ctx.lookup(12345);
    try std.testing.expect(found == &val);

    const not_found = ctx.lookup(99999);
    try std.testing.expect(not_found == null);
}

test "context copy" {
    var ctx1 = Context.init(std.testing.allocator);
    defer ctx1.deinit();

    var val: u32 = 42;
    try ctx1.set(12345, &val);

    var ctx2 = try Context.copy(std.testing.allocator, &ctx1);
    defer ctx2.deinit();

    // ctx2 should see parent's value
    const found = ctx2.lookup(12345);
    try std.testing.expect(found == &val);

    // Setting in ctx2 doesn't affect ctx1
    var new_val: u32 = 100;
    try ctx2.set(12345, &new_val);

    const ctx1_val = ctx1.lookup(12345);
    try std.testing.expect(ctx1_val == &val);

    const ctx2_val = ctx2.lookup(12345);
    try std.testing.expect(ctx2_val == &new_val);
}

test "context stack" {
    var stack = ContextStack.init(std.testing.allocator);
    defer stack.deinit();

    var ctx1 = Context.init(std.testing.allocator);
    defer ctx1.deinit();

    var ctx2 = Context.init(std.testing.allocator);
    defer ctx2.deinit();

    try std.testing.expectEqual(@as(usize, 0), stack.depth());
    try std.testing.expect(stack.getCurrent() == null);

    try stack.enter(&ctx1);
    try std.testing.expectEqual(@as(usize, 1), stack.depth());
    try std.testing.expect(stack.getCurrent() == &ctx1);

    try stack.enter(&ctx2);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());
    try std.testing.expect(stack.getCurrent() == &ctx2);

    const exited = stack.exit();
    try std.testing.expect(exited == &ctx2);
    try std.testing.expect(stack.getCurrent() == &ctx1);
}

test "token cannot be reused" {
    var cv = ContextVar.init("test_var", null);

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    var val1: u32 = 100;
    var token = try cv.set(&ctx, &val1);

    try cv.reset(&ctx, &token);

    // Token is used, cannot reset again
    try std.testing.expectError(ContextError.RuntimeError, cv.reset(&ctx, &token));
}
