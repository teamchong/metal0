//! CPython source: Lib/pdb.py
//!
//! Provides an interactive debugger for Python programs.
//!
//! Mirrors: CPython Lib/pdb.py

const std = @import("std");

// ============================================================================
// Breakpoint
// ============================================================================

/// Breakpoint representation
pub const Breakpoint = struct {
    number: u32,
    file: []const u8,
    line: usize,
    temporary: bool,
    enabled: bool,
    hits: u32,
    ignore: u32,
    condition: ?[]const u8,

    pub fn init(number: u32, file: []const u8, line: usize, temporary: bool) Breakpoint {
        return .{
            .number = number,
            .file = file,
            .line = line,
            .temporary = temporary,
            .enabled = true,
            .hits = 0,
            .ignore = 0,
            .condition = null,
        };
    }

    pub fn enable(self: *Breakpoint) void {
        self.enabled = true;
    }

    pub fn disable(self: *Breakpoint) void {
        self.enabled = false;
    }

    pub fn bpformat(self: *const Breakpoint, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        const disp = if (self.temporary) "del" else "keep";
        const enab = if (self.enabled) "yes" else "no";

        try result.writer().print("{d:>4} breakpoint   {s} {s}   at {s}:{d}", .{
            self.number,
            disp,
            enab,
            self.file,
            self.line,
        });

        if (self.condition) |cond| {
            try result.writer().print("\n\tstop only if {s}", .{cond});
        }

        if (self.ignore > 0) {
            try result.writer().print("\n\tignore next {d} hits", .{self.ignore});
        }

        if (self.hits > 0) {
            const ss = if (self.hits > 1) "s" else "";
            try result.writer().print("\n\tbreakpoint already hit {d} time{s}", .{ self.hits, ss });
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Stack Frame
// ============================================================================

/// Stack frame representation
pub const Frame = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    locals: std.StringHashMap([]const u8),
    globals: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, function: []const u8) Frame {
        return .{
            .filename = filename,
            .lineno = lineno,
            .function = function,
            .locals = std.StringHashMap([]const u8).init(allocator),
            .globals = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Frame) void {
        self.locals.deinit();
        self.globals.deinit();
    }
};

// ============================================================================
// Pdb - Python Debugger
// ============================================================================

/// Python debugger
pub const Pdb = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Breakpoints
    breakpoints: std.ArrayList(Breakpoint),
    bp_counter: u32,

    // State
    stack: std.ArrayList(Frame),
    curindex: usize,
    curframe: ?*Frame,

    // Settings
    skip: []const []const u8,
    commands: std.AutoHashMap(u32, []const []const u8),
    commands_doprompt: std.AutoHashMap(u32, bool),
    commands_silent: std.AutoHashMap(u32, bool),

    // I/O
    prompt: []const u8,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,

    // Aliases
    aliases: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, skip: ?[]const []const u8) Self {
        return .{
            .allocator = allocator,
            .breakpoints = std.ArrayList(Breakpoint).init(allocator),
            .bp_counter = 0,
            .stack = std.ArrayList(Frame).init(allocator),
            .curindex = 0,
            .curframe = null,
            .skip = skip orelse &[_][]const u8{},
            .commands = std.AutoHashMap(u32, []const []const u8).init(allocator),
            .commands_doprompt = std.AutoHashMap(u32, bool).init(allocator),
            .commands_silent = std.AutoHashMap(u32, bool).init(allocator),
            .prompt = "(Pdb) ",
            .stdin = std.io.getStdIn().reader(),
            .stdout = std.io.getStdOut().writer(),
            .aliases = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.breakpoints.deinit();
        for (self.stack.items) |*frame| {
            frame.deinit();
        }
        self.stack.deinit();
        self.commands.deinit();
        self.commands_doprompt.deinit();
        self.commands_silent.deinit();
        self.aliases.deinit();
    }

    // ========================================================================
    // Breakpoint Management
    // ========================================================================

    /// Set a breakpoint
    pub fn setBreak(self: *Self, filename: []const u8, lineno: usize, temporary: bool, cond: ?[]const u8) !u32 {
        self.bp_counter += 1;
        var bp = Breakpoint.init(self.bp_counter, filename, lineno, temporary);
        bp.condition = cond;
        try self.breakpoints.append(bp);
        return self.bp_counter;
    }

    /// Clear a breakpoint by number
    pub fn clearBreak(self: *Self, number: u32) bool {
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.number == number) {
                _ = self.breakpoints.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Clear all breakpoints
    pub fn clearAllBreaks(self: *Self) void {
        self.breakpoints.clearRetainingCapacity();
    }

    /// Get breakpoint by number
    pub fn getBreak(self: *Self, number: u32) ?*Breakpoint {
        for (self.breakpoints.items) |*bp| {
            if (bp.number == number) {
                return bp;
            }
        }
        return null;
    }

    /// Get all breakpoints at a location
    pub fn getBreaks(self: *Self, filename: []const u8, lineno: usize) []Breakpoint {
        var result = std.ArrayList(Breakpoint).init(self.allocator);
        for (self.breakpoints.items) |bp| {
            if (std.mem.eql(u8, bp.file, filename) and bp.line == lineno) {
                result.append(bp) catch continue;
            }
        }
        return result.toOwnedSlice() catch &[_]Breakpoint{};
    }

    // ========================================================================
    // Debugger Commands
    // ========================================================================

    /// Break command (b/break)
    pub fn do_break(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            // List all breakpoints
            if (self.breakpoints.items.len == 0) {
                try self.message("No breakpoints.");
                return;
            }
            try self.message("Num Type         Disp Enb   Where");
            for (self.breakpoints.items) |*bp| {
                const formatted = try bp.bpformat(self.allocator);
                defer self.allocator.free(formatted);
                try self.message(formatted);
            }
        } else {
            // Parse location
            const parsed = parseBreakArg(arg);
            const number = try self.setBreak(parsed.filename, parsed.lineno, false, parsed.condition);
            try self.stdout.print("Breakpoint {d} at {s}:{d}\n", .{ number, parsed.filename, parsed.lineno });
        }
    }

    /// Clear command (cl/clear)
    pub fn do_clear(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            self.clearAllBreaks();
            try self.message("Cleared all breakpoints.");
        } else {
            const number = std.fmt.parseInt(u32, arg, 10) catch {
                try self.error_msg("Invalid breakpoint number");
                return;
            };
            if (self.clearBreak(number)) {
                try self.stdout.print("Deleted breakpoint {d}\n", .{number});
            } else {
                try self.stdout.print("No breakpoint numbered {d}\n", .{number});
            }
        }
    }

    /// Continue command (c/cont/continue)
    pub fn do_continue(self: *Self, arg: []const u8) !void {
        _ = arg;
        _ = self;
        // Would continue execution
    }

    /// Step command (s/step)
    pub fn do_step(self: *Self, arg: []const u8) !void {
        _ = arg;
        _ = self;
        // Would step into
    }

    /// Next command (n/next)
    pub fn do_next(self: *Self, arg: []const u8) !void {
        _ = arg;
        _ = self;
        // Would step over
    }

    /// Return command (r/return)
    pub fn do_return(self: *Self, arg: []const u8) !void {
        _ = arg;
        _ = self;
        // Would continue until return
    }

    /// Where command (w/where/bt)
    pub fn do_where(self: *Self, arg: []const u8) !void {
        _ = arg;
        try self.printStack();
    }

    /// Up command (u/up)
    pub fn do_up(self: *Self, arg: []const u8) !void {
        const count = if (arg.len > 0)
            std.fmt.parseInt(usize, arg, 10) catch 1
        else
            1;

        if (self.curindex >= count) {
            self.curindex -= count;
            self.curframe = &self.stack.items[self.curindex];
            try self.printFrameInfo();
        } else {
            try self.error_msg("Oldest frame");
        }
    }

    /// Down command (d/down)
    pub fn do_down(self: *Self, arg: []const u8) !void {
        const count = if (arg.len > 0)
            std.fmt.parseInt(usize, arg, 10) catch 1
        else
            1;

        if (self.curindex + count < self.stack.items.len) {
            self.curindex += count;
            self.curframe = &self.stack.items[self.curindex];
            try self.printFrameInfo();
        } else {
            try self.error_msg("Newest frame");
        }
    }

    /// List command (l/list)
    pub fn do_list(self: *Self, arg: []const u8) !void {
        _ = arg;
        if (self.curframe) |frame| {
            try self.stdout.print("{s}:{d}\n", .{ frame.filename, frame.lineno });
            // Would list source code around current line
        } else {
            try self.error_msg("No current frame");
        }
    }

    /// Print command (p/print)
    pub fn do_print(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            try self.error_msg("*** No expression given");
            return;
        }
        // Would evaluate expression
        try self.stdout.print("{s}\n", .{arg});
    }

    /// Pretty print command (pp)
    pub fn do_pp(self: *Self, arg: []const u8) !void {
        try self.do_print(arg);
    }

    /// Quit command (q/quit/exit)
    pub fn do_quit(self: *Self, arg: []const u8) !void {
        _ = arg;
        _ = self;
        // Would exit debugger
    }

    /// Help command (h/help)
    pub fn do_help(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            try self.message("Documented commands (type help <topic>):");
            try self.message("=========================================");
            try self.message("break clear continue down help list next print");
            try self.message("pp quit return step up where");
        } else {
            // Would show help for specific command
            try self.stdout.print("Help for: {s}\n", .{arg});
        }
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    fn parseBreakArg(arg: []const u8) struct { filename: []const u8, lineno: usize, condition: ?[]const u8 } {
        // Simple parsing: filename:lineno or just lineno
        if (std.mem.indexOf(u8, arg, ":")) |colon| {
            const filename = arg[0..colon];
            const rest = arg[colon + 1 ..];
            const lineno = std.fmt.parseInt(usize, rest, 10) catch 1;
            return .{ .filename = filename, .lineno = lineno, .condition = null };
        } else {
            const lineno = std.fmt.parseInt(usize, arg, 10) catch 1;
            return .{ .filename = "<stdin>", .lineno = lineno, .condition = null };
        }
    }

    fn printStack(self: *Self) !void {
        for (self.stack.items, 0..) |frame, i| {
            const marker = if (i == self.curindex) ">" else " ";
            try self.stdout.print("{s} {s}({d}){s}()\n", .{ marker, frame.filename, frame.lineno, frame.function });
        }
    }

    fn printFrameInfo(self: *Self) !void {
        if (self.curframe) |frame| {
            try self.stdout.print("> {s}({d}){s}()\n", .{ frame.filename, frame.lineno, frame.function });
        }
    }

    fn message(self: *Self, msg: []const u8) !void {
        try self.stdout.print("{s}\n", .{msg});
    }

    fn error_msg(self: *Self, msg: []const u8) !void {
        try self.stdout.print("*** {s}\n", .{msg});
    }

    // ========================================================================
    // Main Entry Points
    // ========================================================================

    /// Run the debugger on a script
    pub fn run(self: *Self, cmd: []const u8) !void {
        _ = self;
        _ = cmd;
        // Would execute command under debugger
    }

    /// Start debugging at the call site
    pub fn setTrace(self: *Self) void {
        _ = self;
        // Would set trace function
    }

    /// Post-mortem debugging
    pub fn postMortem(self: *Self) !void {
        _ = self;
        // Would examine exception traceback
    }

    /// Interactive debugging session
    pub fn interact(self: *Self) !void {
        while (true) {
            try self.stdout.print("{s}", .{self.prompt});

            var buf: [1024]u8 = undefined;
            const line = self.stdin.readUntilDelimiterOrEof(&buf, '\n') catch break;

            if (line == null) break;

            const trimmed = std.mem.trim(u8, line.?, " \t\r\n");
            if (trimmed.len == 0) continue;

            // Parse command
            const space = std.mem.indexOf(u8, trimmed, " ");
            const cmd = if (space) |s| trimmed[0..s] else trimmed;
            const arg = if (space) |s| std.mem.trim(u8, trimmed[s + 1 ..], " \t") else "";

            // Dispatch
            if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "quit")) {
                break;
            } else if (std.mem.eql(u8, cmd, "h") or std.mem.eql(u8, cmd, "help")) {
                try self.do_help(arg);
            } else if (std.mem.eql(u8, cmd, "b") or std.mem.eql(u8, cmd, "break")) {
                try self.do_break(arg);
            } else if (std.mem.eql(u8, cmd, "cl") or std.mem.eql(u8, cmd, "clear")) {
                try self.do_clear(arg);
            } else if (std.mem.eql(u8, cmd, "c") or std.mem.eql(u8, cmd, "continue")) {
                try self.do_continue(arg);
            } else if (std.mem.eql(u8, cmd, "s") or std.mem.eql(u8, cmd, "step")) {
                try self.do_step(arg);
            } else if (std.mem.eql(u8, cmd, "n") or std.mem.eql(u8, cmd, "next")) {
                try self.do_next(arg);
            } else if (std.mem.eql(u8, cmd, "r") or std.mem.eql(u8, cmd, "return")) {
                try self.do_return(arg);
            } else if (std.mem.eql(u8, cmd, "w") or std.mem.eql(u8, cmd, "where") or std.mem.eql(u8, cmd, "bt")) {
                try self.do_where(arg);
            } else if (std.mem.eql(u8, cmd, "u") or std.mem.eql(u8, cmd, "up")) {
                try self.do_up(arg);
            } else if (std.mem.eql(u8, cmd, "d") or std.mem.eql(u8, cmd, "down")) {
                try self.do_down(arg);
            } else if (std.mem.eql(u8, cmd, "l") or std.mem.eql(u8, cmd, "list")) {
                try self.do_list(arg);
            } else if (std.mem.eql(u8, cmd, "p") or std.mem.eql(u8, cmd, "print")) {
                try self.do_print(arg);
            } else if (std.mem.eql(u8, cmd, "pp")) {
                try self.do_pp(arg);
            } else {
                try self.stdout.print("*** Unknown command: {s}\n", .{cmd});
            }
        }
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Convenience function to set a breakpoint
pub fn set_trace() void {
    // Would set trace function
}

/// Post-mortem debugging of last exception
pub fn pm() void {
    // Would start post-mortem debugging
}

/// Run a script under the debugger
pub fn run(statement: []const u8, globals: ?*anyopaque, locals: ?*anyopaque) void {
    _ = statement;
    _ = globals;
    _ = locals;
    // Would run statement under debugger
}

/// Run a script file under the debugger
pub fn runscript(allocator: std.mem.Allocator, filename: []const u8) !void {
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();
    _ = filename;
    // Would load and run file under debugger
}

// ============================================================================
// Tests
// ============================================================================

test "Breakpoint init" {
    const bp = Breakpoint.init(1, "test.py", 10, false);
    try std.testing.expectEqual(@as(u32, 1), bp.number);
    try std.testing.expectEqualStrings("test.py", bp.file);
    try std.testing.expectEqual(@as(usize, 10), bp.line);
    try std.testing.expect(!bp.temporary);
    try std.testing.expect(bp.enabled);
}

test "Breakpoint enable/disable" {
    var bp = Breakpoint.init(1, "test.py", 10, false);

    try std.testing.expect(bp.enabled);
    bp.disable();
    try std.testing.expect(!bp.enabled);
    bp.enable();
    try std.testing.expect(bp.enabled);
}

test "Pdb init" {
    const allocator = std.testing.allocator;
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();

    try std.testing.expectEqualStrings("(Pdb) ", pdb.prompt);
    try std.testing.expectEqual(@as(usize, 0), pdb.breakpoints.items.len);
}

test "Pdb setBreak" {
    const allocator = std.testing.allocator;
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();

    const num = try pdb.setBreak("test.py", 10, false, null);
    try std.testing.expectEqual(@as(u32, 1), num);
    try std.testing.expectEqual(@as(usize, 1), pdb.breakpoints.items.len);
}

test "Pdb clearBreak" {
    const allocator = std.testing.allocator;
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();

    const num = try pdb.setBreak("test.py", 10, false, null);
    try std.testing.expect(pdb.clearBreak(num));
    try std.testing.expectEqual(@as(usize, 0), pdb.breakpoints.items.len);
}

test "Frame init" {
    const allocator = std.testing.allocator;
    var frame = Frame.init(allocator, "test.py", 10, "main");
    defer frame.deinit();

    try std.testing.expectEqualStrings("test.py", frame.filename);
    try std.testing.expectEqual(@as(usize, 10), frame.lineno);
    try std.testing.expectEqualStrings("main", frame.function);
}
