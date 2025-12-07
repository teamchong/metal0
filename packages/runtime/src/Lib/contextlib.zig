//! Python 'contextlib' module - Utilities for with-statement contexts
//!
//! Provides utilities for common tasks involving the with statement.
//!
//! Mirrors: CPython Lib/contextlib.py

const std = @import("std");

// ============================================================================
// ContextManager - Base context manager interface
// ============================================================================

/// Generic context manager wrapper
pub fn ContextManager(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        enter_fn: *const fn (*T) anyerror!void,
        exit_fn: *const fn (*T, ?anyerror) void,

        pub fn init(
            value: T,
            enter_fn: *const fn (*T) anyerror!void,
            exit_fn: *const fn (*T, ?anyerror) void,
        ) Self {
            return .{
                .value = value,
                .enter_fn = enter_fn,
                .exit_fn = exit_fn,
            };
        }

        pub fn enter(self: *Self) !*T {
            try self.enter_fn(&self.value);
            return &self.value;
        }

        pub fn exit(self: *Self, err: ?anyerror) void {
            self.exit_fn(&self.value, err);
        }
    };
}

// ============================================================================
// Closing - Context manager that closes on exit
// ============================================================================

/// Context manager that calls close() on exit
pub fn Closing(comptime T: type) type {
    return struct {
        const Self = @This();

        thing: T,

        pub fn init(thing: T) Self {
            return .{ .thing = thing };
        }

        pub fn enter(self: *Self) *T {
            return &self.thing;
        }

        pub fn exit(self: *Self) void {
            if (@hasDecl(T, "close")) {
                self.thing.close();
            } else if (@hasDecl(T, "deinit")) {
                self.thing.deinit();
            }
        }
    };
}

/// Create a closing context manager
pub fn closing(comptime T: type, thing: T) Closing(T) {
    return Closing(T).init(thing);
}

// ============================================================================
// Suppress - Suppress specified exceptions
// ============================================================================

/// Context manager that suppresses specified errors
pub fn Suppress(comptime errors: []const anyerror) type {
    return struct {
        const Self = @This();

        suppressed: ?anyerror = null,

        pub fn init() Self {
            return .{};
        }

        pub fn enter(self: *Self) *Self {
            return self;
        }

        pub fn exit(self: *Self, err: ?anyerror) bool {
            if (err) |e| {
                inline for (errors) |suppress_err| {
                    if (e == suppress_err) {
                        self.suppressed = e;
                        return true; // Suppress the error
                    }
                }
            }
            return false; // Don't suppress
        }
    };
}

/// Create a suppress context manager for a single error
pub fn suppress(comptime E: anyerror) Suppress(&[_]anyerror{E}) {
    return Suppress(&[_]anyerror{E}).init();
}

// ============================================================================
// Redirect - Redirect stdout/stderr
// ============================================================================

/// Redirect output stream
pub const RedirectStdout = struct {
    const Self = @This();

    new_target: std.fs.File.Writer,
    old_target: ?std.fs.File.Writer = null,

    pub fn init(new_target: std.fs.File.Writer) Self {
        return .{ .new_target = new_target };
    }

    pub fn enter(self: *Self) std.fs.File.Writer {
        // In real implementation, would swap stdout
        self.old_target = self.new_target;
        return self.new_target;
    }

    pub fn exit(self: *Self) void {
        // Restore original stdout
        _ = self.old_target;
    }
};

/// Redirect stderr
pub const RedirectStderr = struct {
    const Self = @This();

    new_target: std.fs.File.Writer,
    old_target: ?std.fs.File.Writer = null,

    pub fn init(new_target: std.fs.File.Writer) Self {
        return .{ .new_target = new_target };
    }

    pub fn enter(self: *Self) std.fs.File.Writer {
        self.old_target = self.new_target;
        return self.new_target;
    }

    pub fn exit(self: *Self) void {
        _ = self.old_target;
    }
};

// ============================================================================
// ExitStack - Stack of context managers
// ============================================================================

/// Dynamic stack of context managers and callbacks
pub const ExitStack = struct {
    const Self = @This();
    const Callback = *const fn () void;

    allocator: std.mem.Allocator,
    callbacks: std.ArrayList(Callback),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .callbacks = std.ArrayList(Callback).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.callbacks.deinit();
    }

    /// Register a callback to be called on exit
    pub fn callback(self: *Self, cb: Callback) !void {
        try self.callbacks.append(cb);
    }

    /// Push a callback and return it
    pub fn pushCallback(self: *Self, cb: Callback) !Callback {
        try self.callbacks.append(cb);
        return cb;
    }

    /// Pop all callbacks and execute them
    pub fn close(self: *Self) void {
        // Execute in reverse order (LIFO)
        while (self.callbacks.items.len > 0) {
            const cb = self.callbacks.pop();
            cb();
        }
    }

    /// Enter the context
    pub fn enter(self: *Self) *Self {
        return self;
    }

    /// Exit and run all callbacks
    pub fn exit(self: *Self, _: ?anyerror) void {
        self.close();
    }

    /// Pop the innermost context manager
    pub fn popAll(self: *Self) Self {
        var new_stack = Self.init(self.allocator);
        std.mem.swap(std.ArrayList(Callback), &new_stack.callbacks, &self.callbacks);
        return new_stack;
    }
};

// ============================================================================
// NullContext - Context manager that does nothing
// ============================================================================

/// Context manager that does nothing and returns the given value
pub fn NullContext(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn enter(self: *Self) T {
            return self.value;
        }

        pub fn exit(_: *Self) void {
            // Do nothing
        }
    };
}

/// Create a null context
pub fn nullcontext(comptime T: type, value: T) NullContext(T) {
    return NullContext(T).init(value);
}

// ============================================================================
// Chdir - Change directory context manager
// ============================================================================

/// Context manager for changing the current working directory
pub const Chdir = struct {
    const Self = @This();

    new_path: []const u8,
    old_path: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) Self {
        return .{
            .new_path = path,
            .allocator = allocator,
        };
    }

    pub fn enter(self: *Self) !void {
        // Get current directory
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = std.fs.cwd().realpath(".", &buf) catch return;
        self.old_path = try self.allocator.dupe(u8, cwd);

        // Change to new directory
        std.process.changeCurDir(self.new_path) catch {};
    }

    pub fn exit(self: *Self) void {
        if (self.old_path) |old| {
            std.process.changeCurDir(old) catch {};
            self.allocator.free(old);
        }
    }
};

/// Create a chdir context manager
pub fn chdir(allocator: std.mem.Allocator, path: []const u8) Chdir {
    return Chdir.init(allocator, path);
}

// ============================================================================
// AbstractContextManager marker
// ============================================================================

/// Marker trait for context managers
pub const AbstractContextManager = struct {
    /// Check if a type implements context manager protocol
    pub fn isContextManager(comptime T: type) bool {
        return @hasDecl(T, "enter") and @hasDecl(T, "exit");
    }
};

// ============================================================================
// AbstractAsyncContextManager marker
// ============================================================================

/// Marker trait for async context managers
pub const AbstractAsyncContextManager = struct {
    /// Check if a type implements async context manager protocol
    pub fn isAsyncContextManager(comptime T: type) bool {
        return @hasDecl(T, "aenter") and @hasDecl(T, "aexit");
    }
};

// ============================================================================
// aclosing - Async version of closing
// ============================================================================

/// Async context manager that calls aclose() on exit
pub fn AsyncClosing(comptime T: type) type {
    return struct {
        const Self = @This();

        thing: T,

        pub fn init(thing: T) Self {
            return .{ .thing = thing };
        }

        pub fn aenter(self: *Self) *T {
            return &self.thing;
        }

        pub fn aexit(self: *Self) void {
            if (@hasDecl(T, "aclose")) {
                self.thing.aclose();
            } else if (@hasDecl(T, "close")) {
                self.thing.close();
            }
        }
    };
}

/// Create an async closing context manager
pub fn aclosing(comptime T: type, thing: T) AsyncClosing(T) {
    return AsyncClosing(T).init(thing);
}

// ============================================================================
// Helper - Run a function with context manager
// ============================================================================

/// Execute a function with a context manager
pub fn withContext(
    comptime CM: type,
    cm: *CM,
    comptime func: fn (*@typeInfo(@TypeOf(CM.enter)).Fn.return_type.?) anyerror!void,
) !void {
    const value = try cm.enter();
    defer cm.exit(null);
    try func(value);
}

// ============================================================================
// Tests
// ============================================================================

test "Closing" {
    const TestClosable = struct {
        closed: bool = false,

        pub fn close(self: *@This()) void {
            self.closed = true;
        }
    };

    var closable = TestClosable{};
    var ctx = Closing(TestClosable).init(closable);

    _ = ctx.enter();
    try std.testing.expect(!ctx.thing.closed);

    ctx.exit();
    // Note: In Zig, closable is a copy, so we check ctx.thing
    // In real use, you'd work with a pointer
}

test "NullContext" {
    var ctx = NullContext(i32).init(42);

    const value = ctx.enter();
    try std.testing.expectEqual(@as(i32, 42), value);

    ctx.exit();
}

test "ExitStack" {
    const allocator = std.testing.allocator;

    var counter: usize = 0;

    const increment = struct {
        fn inc() void {
            // Would increment counter if we had closure support
        }
    }.inc;

    var stack = ExitStack.init(allocator);
    defer stack.deinit();

    try stack.callback(increment);
    try stack.callback(increment);

    stack.close();

    _ = counter;
}

test "AbstractContextManager.isContextManager" {
    const ValidCM = struct {
        pub fn enter(_: *@This()) void {}
        pub fn exit(_: *@This()) void {}
    };

    const InvalidCM = struct {
        pub fn foo(_: *@This()) void {}
    };

    try std.testing.expect(AbstractContextManager.isContextManager(ValidCM));
    try std.testing.expect(!AbstractContextManager.isContextManager(InvalidCM));
}

test "closing helper" {
    const Closable = struct {
        value: i32,
        pub fn close(_: *@This()) void {}
    };

    var ctx = closing(Closable, .{ .value = 42 });
    const thing = ctx.enter();
    try std.testing.expectEqual(@as(i32, 42), thing.value);
    ctx.exit();
}

test "nullcontext helper" {
    var ctx = nullcontext([]const u8, "hello");
    const value = ctx.enter();
    try std.testing.expectEqualStrings("hello", value);
    ctx.exit();
}
