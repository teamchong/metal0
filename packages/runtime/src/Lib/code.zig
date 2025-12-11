//! CPython source: Lib/code.py
//!
//! Provides classes for interactive Python sessions.
//!
//! Mirrors: CPython Lib/code.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// InteractiveInterpreter
// ============================================================================

/// Base class for interactive code execution
pub const InteractiveInterpreter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    locals: hashmap_helper.StringHashMap([]const u8),
    filename: []const u8,
    compile: ?*const fn (source: []const u8, filename: []const u8, mode: []const u8) anyerror!?CompiledCode,

    pub const CompiledCode = struct {
        source: []const u8,
        filename: []const u8,
        mode: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, locals: ?hashmap_helper.StringHashMap([]const u8)) Self {
        return .{
            .allocator = allocator,
            .locals = locals orelse hashmap_helper.StringHashMap([]const u8).init(allocator),
            .filename = "<stdin>",
            .compile = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.locals.deinit();
    }

    /// Execute source code
    pub fn runsource(self: *Self, source: []const u8, filename: ?[]const u8, symbol: []const u8) !bool {
        const fname = filename orelse self.filename;

        // Try to compile
        const code = try self.compileSource(source, fname, symbol);
        if (code == null) {
            // Incomplete input
            return true;
        }

        // Execute the compiled code
        try self.runcode(code.?);
        return false;
    }

    /// Compile source code
    fn compileSource(self: *Self, source: []const u8, filename: []const u8, symbol: []const u8) !?CompiledCode {
        if (self.compile) |comp| {
            return try comp(source, filename, symbol);
        }

        // Default: just wrap the source
        return CompiledCode{
            .source = source,
            .filename = filename,
            .mode = symbol,
        };
    }

    /// Execute compiled code
    /// In AOT context, this displays the code that would be executed
    /// Real execution happens in compiled binaries
    pub fn runcode(self: *Self, code: CompiledCode) !void {
        // In an AOT compiler, we can't dynamically execute code
        // Instead, show what would be executed and track execution state
        if (self.exec_callback) |callback| {
            // If a callback is registered, use it
            try callback(code);
        } else {
            // Default behavior: display the code for inspection
            try self.write(">>> ");
            try self.write(code.source);
            try self.write("\n");
            // Mark as executed for interactive session tracking
            self.last_executed = code.source;
        }
    }

    // Callback for actual execution (set by compiled runtime)
    exec_callback: ?*const fn (CompiledCode) anyerror!void = null,
    // Track last executed code
    last_executed: ?[]const u8 = null,

    /// Display exception information
    pub fn showtraceback(self: *Self) !void {
        try self.write("Traceback (most recent call last):\n");
        try self.write("  ...\n");
    }

    /// Display syntax error
    pub fn showsyntaxerror(self: *Self, filename: ?[]const u8) !void {
        const fname = filename orelse self.filename;
        try self.write("  File \"");
        try self.write(fname);
        try self.write("\", line 1\n");
        try self.write("SyntaxError: invalid syntax\n");
    }

    /// Write to output
    pub fn write(self: *Self, data: []const u8) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(data);
    }

    /// Reset the buffer (clear accumulated incomplete input)
    pub fn resetbuffer(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }
};

// ============================================================================
// InteractiveConsole
// ============================================================================

/// Interactive console with input buffering
pub const InteractiveConsole = struct {
    const Self = @This();

    interpreter: InteractiveInterpreter,
    buffer: std.ArrayList([]const u8),
    banner: []const u8,
    exitmsg: []const u8,
    raw_input: bool,

    pub fn init(allocator: std.mem.Allocator, locals: ?hashmap_helper.StringHashMap([]const u8), filename: ?[]const u8) Self {
        var interp = InteractiveInterpreter.init(allocator, locals);
        if (filename) |f| {
            interp.filename = f;
        }

        return .{
            .interpreter = interp,
            .buffer = std.ArrayList([]const u8).init(allocator),
            .banner = "Python 3.x (Metal0 Runtime)\nType \"help\", \"copyright\", \"credits\" or \"license\" for more information.",
            .exitmsg = "now exiting InteractiveConsole...",
            .raw_input = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.interpreter.deinit();
        self.buffer.deinit();
    }

    /// Main interaction loop
    pub fn interact(self: *Self, banner: ?[]const u8, exitmsg: ?[]const u8) !void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        // Print banner
        const actual_banner = banner orelse self.banner;
        if (actual_banner.len > 0) {
            try stdout.print("{s}\n", .{actual_banner});
        }

        var more = false;
        while (true) {
            // Print prompt
            const prompt = if (more) "... " else ">>> ";
            try stdout.print("{s}", .{prompt});

            // Read input
            var buf: [4096]u8 = undefined;
            const line = stdin.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (line == null) {
                // EOF
                try stdout.writeAll("\n");
                break;
            }

            // Push to buffer and try to execute
            const result = try self.push(line.?);
            more = result;
        }

        // Print exit message
        const actual_exitmsg = exitmsg orelse self.exitmsg;
        if (actual_exitmsg.len > 0) {
            try stdout.print("{s}\n", .{actual_exitmsg});
        }
    }

    /// Push a line to the buffer and try to execute
    pub fn push(self: *Self, line: []const u8) !bool {
        try self.buffer.append(line);

        // Join buffer lines
        const source = try self.getSource();
        defer self.interpreter.allocator.free(source);

        const more = try self.interpreter.runsource(source, null, "single");

        if (!more) {
            self.resetbuffer();
        }

        return more;
    }

    /// Get source from buffer
    fn getSource(self: *Self) ![]const u8 {
        var result = std.ArrayList(u8).init(self.interpreter.allocator);
        errdefer result.deinit();

        for (self.buffer.items, 0..) |line, i| {
            if (i > 0) {
                try result.append('\n');
            }
            try result.appendSlice(line);
        }

        return result.toOwnedSlice();
    }

    /// Reset the input buffer
    pub fn resetbuffer(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Read a line of input
    pub fn raw_input_prompt(self: *Self, prompt: []const u8) !?[]const u8 {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        try stdout.writeAll(prompt);

        var buf: [4096]u8 = undefined;
        return stdin.readUntilDelimiterOrEof(&buf, '\n') catch null;
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Start an interactive console
pub fn interact(allocator: std.mem.Allocator, banner: ?[]const u8, readfunc: ?*const fn () ?[]const u8, local: ?hashmap_helper.StringHashMap([]const u8), exitmsg: ?[]const u8) !void {
    _ = readfunc;
    var console = InteractiveConsole.init(allocator, local, null);
    defer console.deinit();
    try console.interact(banner, exitmsg);
}

/// Compile source code interactively
pub fn compile_command(source: []const u8, filename: ?[]const u8, symbol: ?[]const u8) !?InteractiveInterpreter.CompiledCode {
    const fname = filename orelse "<input>";
    const sym = symbol orelse "single";

    // Check for incomplete input (very simplified)
    if (source.len > 0 and source[source.len - 1] == ':') {
        return null; // Incomplete
    }

    return InteractiveInterpreter.CompiledCode{
        .source = source,
        .filename = fname,
        .mode = sym,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "InteractiveInterpreter init" {
    const allocator = std.testing.allocator;
    var interp = InteractiveInterpreter.init(allocator, null);
    defer interp.deinit();

    try std.testing.expectEqualStrings("<stdin>", interp.filename);
}

test "InteractiveConsole init" {
    const allocator = std.testing.allocator;
    var console = InteractiveConsole.init(allocator, null, null);
    defer console.deinit();

    try std.testing.expect(console.raw_input);
    try std.testing.expectEqual(@as(usize, 0), console.buffer.items.len);
}

test "InteractiveConsole resetbuffer" {
    const allocator = std.testing.allocator;
    var console = InteractiveConsole.init(allocator, null, null);
    defer console.deinit();

    try console.buffer.append("test");
    try std.testing.expectEqual(@as(usize, 1), console.buffer.items.len);

    console.resetbuffer();
    try std.testing.expectEqual(@as(usize, 0), console.buffer.items.len);
}

test "compile_command complete" {
    const result = try compile_command("print('hello')", null, null);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("print('hello')", result.?.source);
}

test "compile_command incomplete" {
    const result = try compile_command("if True:", null, null);
    try std.testing.expect(result == null);
}
