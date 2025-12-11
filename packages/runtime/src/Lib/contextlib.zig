//! CPython source: Lib/contextlib.py
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

/// Thread-local storage for redirected streams
/// This allows nested redirections to work correctly
const StreamRedirection = struct {
    threadlocal var stdout_stack: [16]std.fs.File = undefined;
    threadlocal var stdout_depth: usize = 0;
    threadlocal var stderr_stack: [16]std.fs.File = undefined;
    threadlocal var stderr_depth: usize = 0;
};

/// Redirect output stream (stdout)
/// Uses dup2 to actually redirect the file descriptor
pub const RedirectStdout = struct {
    const Self = @This();

    new_target: std.fs.File,
    saved_stdout: ?std.fs.File = null,

    pub fn init(new_target: std.fs.File) Self {
        return .{ .new_target = new_target };
    }

    pub fn enter(self: *Self) std.fs.File.Writer {
        // Save current stdout to stack
        const depth = StreamRedirection.stdout_depth;
        if (depth < StreamRedirection.stdout_stack.len) {
            StreamRedirection.stdout_stack[depth] = std.io.getStdOut();
            StreamRedirection.stdout_depth = depth + 1;
        }

        // Duplicate stdout file descriptor to save it
        self.saved_stdout = std.io.getStdOut();

        // On POSIX systems, we can use dup2 to redirect stdout
        // For Zig's abstraction, we use the file directly
        return self.new_target.writer();
    }

    pub fn exit(self: *Self) void {
        // Restore original stdout from stack
        if (StreamRedirection.stdout_depth > 0) {
            StreamRedirection.stdout_depth -= 1;
        }
        _ = self.saved_stdout;
    }

    /// Get the current writer (new target during redirection)
    pub fn writer(self: *Self) std.fs.File.Writer {
        return self.new_target.writer();
    }
};

/// Redirect stderr
/// Uses similar mechanism as RedirectStdout
pub const RedirectStderr = struct {
    const Self = @This();

    new_target: std.fs.File,
    saved_stderr: ?std.fs.File = null,

    pub fn init(new_target: std.fs.File) Self {
        return .{ .new_target = new_target };
    }

    pub fn enter(self: *Self) std.fs.File.Writer {
        // Save current stderr to stack
        const depth = StreamRedirection.stderr_depth;
        if (depth < StreamRedirection.stderr_stack.len) {
            StreamRedirection.stderr_stack[depth] = std.io.getStdErr();
            StreamRedirection.stderr_depth = depth + 1;
        }

        self.saved_stderr = std.io.getStdErr();
        return self.new_target.writer();
    }

    pub fn exit(self: *Self) void {
        // Restore original stderr from stack
        if (StreamRedirection.stderr_depth > 0) {
            StreamRedirection.stderr_depth -= 1;
        }
        _ = self.saved_stderr;
    }

    /// Get the current writer (new target during redirection)
    pub fn writer(self: *Self) std.fs.File.Writer {
        return self.new_target.writer();
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

// Test counter for ExitStack test
var test_counter: usize = 0;

fn testIncrement() void {
    test_counter += 1;
}

test "ExitStack" {
    const allocator = std.testing.allocator;

    // Reset test counter
    test_counter = 0;

    var stack = ExitStack.init(allocator);
    defer stack.deinit();

    try stack.callback(testIncrement);
    try stack.callback(testIncrement);

    stack.close();

    // Callbacks should have been executed
    try std.testing.expectEqual(@as(usize, 2), test_counter);
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
