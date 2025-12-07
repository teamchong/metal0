//! Python 'contextvars' module - Context Variables
//!
//! Provides context-local state management for async code.
//!
//! Mirrors: CPython Lib/contextvars.py

const std = @import("std");

// ============================================================================
// Token - Used for resetting context variables
// ============================================================================

/// Token returned when setting a ContextVar
pub fn Token(comptime T: type) type {
    return struct {
        const Self = @This();

        var_: *ContextVar(T),
        old_value: ?T,
        used: bool,

        /// Check if this token's old value was MISSING (var was not set)
        pub fn wasMissing(self: Self) bool {
            return self.old_value == null;
        }
    };
}

// ============================================================================
// ContextVar - A context variable
// ============================================================================

/// A context variable that can have different values in different contexts
pub fn ContextVar(comptime T: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        default: ?T,

        // Thread-local storage for the value
        value: std.Thread.LocalStorage(?T),

        /// Create a new context variable
        pub fn init(name: []const u8) Self {
            return .{
                .name = name,
                .default = null,
                .value = .{},
            };
        }

        /// Create with a default value
        pub fn initWithDefault(name: []const u8, default: T) Self {
            return .{
                .name = name,
                .default = default,
                .value = .{},
            };
        }

        /// Get the current value
        pub fn get(self: *Self) ?T {
            if (self.value.get()) |ptr| {
                if (ptr.*) |val| {
                    return val;
                }
            }
            return self.default;
        }

        /// Get the current value, or return default if not set
        pub fn getWithDefault(self: *Self, default: T) T {
            return self.get() orelse default;
        }

        /// Set the value and return a token for resetting
        pub fn set(self: *Self, value: T) Token(T) {
            const old_value = self.get();
            self.value.set(value);
            return .{
                .var_ = self,
                .old_value = old_value,
                .used = false,
            };
        }

        /// Reset to the value captured by the token
        pub fn reset(self: *Self, token: *Token(T)) void {
            if (token.used) return;
            if (token.var_ != self) return;

            if (token.old_value) |old| {
                self.value.set(old);
            } else {
                // Was not set before - clear it
                self.value.set(null);
            }
            token.used = true;
        }
    };
}

// ============================================================================
// Context - A mapping of ContextVars to values
// ============================================================================

/// Immutable context containing context variable values
pub const Context = struct {
    const Self = @This();
    const DataMap = std.StringHashMap(ContextValue);

    allocator: std.mem.Allocator,
    data: DataMap,

    pub const ContextValue = struct {
        ptr: *anyopaque,
        type_id: usize,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .data = DataMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    /// Create a shallow copy of this context
    pub fn copy(self: *const Self) !Self {
        var new_ctx = Self.init(self.allocator);
        var it = self.data.iterator();
        while (it.next()) |entry| {
            try new_ctx.data.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        return new_ctx;
    }

    /// Run a callable in this context
    pub fn run(self: *Self, comptime func: anytype, args: anytype) @TypeOf(@call(.auto, func, args)) {
        // Would set up the context, run the function, then restore
        _ = self;
        return @call(.auto, func, args);
    }

    /// Get number of items in context
    pub fn len(self: *const Self) usize {
        return self.data.count();
    }

    /// Check if context contains a variable
    pub fn contains(self: *const Self, name: []const u8) bool {
        return self.data.contains(name);
    }

    /// Get all keys
    pub fn keys(self: *const Self) []const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.data.keyIterator();
        while (it.next()) |key| {
            result.append(key.*) catch continue;
        }
        return result.toOwnedSlice() catch &[_][]const u8{};
    }

    /// Get all values
    pub fn values(self: *const Self) []const ContextValue {
        var result = std.ArrayList(ContextValue).init(self.allocator);
        var it = self.data.valueIterator();
        while (it.next()) |val| {
            result.append(val.*) catch continue;
        }
        return result.toOwnedSlice() catch &[_]ContextValue{};
    }

    /// Iterate over items
    pub fn items(self: *const Self) DataMap.Iterator {
        return self.data.iterator();
    }
};

// ============================================================================
// copy_context - Get a copy of the current context
// ============================================================================

/// Get a copy of the current context
pub fn copy_context(allocator: std.mem.Allocator) Context {
    // In real implementation, would copy from current async task's context
    return Context.init(allocator);
}

// ============================================================================
// Simplified API for common use cases
// ============================================================================

/// Create a simple string context variable
pub const StringVar = ContextVar([]const u8);

/// Create a simple integer context variable
pub const IntVar = ContextVar(i64);

/// Create a simple boolean context variable
pub const BoolVar = ContextVar(bool);

// ============================================================================
// Context Manager Support
// ============================================================================

/// RAII-style context manager for temporarily setting a context var
pub fn ContextScope(comptime T: type) type {
    return struct {
        const Self = @This();

        var_: *ContextVar(T),
        token: Token(T),

        pub fn enter(var_: *ContextVar(T), value: T) Self {
            return .{
                .var_ = var_,
                .token = var_.set(value),
            };
        }

        pub fn exit(self: *Self) void {
            self.var_.reset(&self.token);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ContextVar init" {
    var cv = ContextVar(i32).init("test_var");
    try std.testing.expectEqualStrings("test_var", cv.name);
    try std.testing.expect(cv.default == null);
}

test "ContextVar with default" {
    var cv = ContextVar(i32).initWithDefault("test_var", 42);
    try std.testing.expectEqual(@as(?i32, 42), cv.default);
}

test "ContextVar getWithDefault" {
    var cv = ContextVar(i32).init("test_var");
    const val = cv.getWithDefault(100);
    try std.testing.expectEqual(@as(i32, 100), val);
}

test "Context init and deinit" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.len());
}

test "Context copy" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var ctx2 = try ctx.copy();
    defer ctx2.deinit();

    try std.testing.expectEqual(ctx.len(), ctx2.len());
}

test "copy_context" {
    const allocator = std.testing.allocator;
    var ctx = copy_context(allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.len());
}

test "Token wasMissing" {
    var cv = ContextVar(i32).init("test");
    var token = cv.set(10);
    try std.testing.expect(token.wasMissing());
}

test "StringVar type alias" {
    var sv = StringVar.init("my_string");
    try std.testing.expectEqualStrings("my_string", sv.name);
}

test "IntVar type alias" {
    var iv = IntVar.initWithDefault("my_int", 42);
    try std.testing.expectEqual(@as(?i64, 42), iv.default);
}

test "BoolVar type alias" {
    var bv = BoolVar.initWithDefault("my_bool", true);
    try std.testing.expectEqual(@as(?bool, true), bv.default);
}
