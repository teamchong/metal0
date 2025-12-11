//! CPython source: Lib/pdb.py
//!
//! Provides an interactive debugger for Python programs.
//!
//! Mirrors: CPython Lib/pdb.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

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
    locals: hashmap_helper.StringHashMap([]const u8),
    globals: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, function: []const u8) Frame {
        return .{
            .filename = filename,
            .lineno = lineno,
            .function = function,
            .locals = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .globals = hashmap_helper.StringHashMap([]const u8).init(allocator),
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
    aliases: hashmap_helper.StringHashMap([]const u8),

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
            .aliases = hashmap_helper.StringHashMap([]const u8).init(allocator),
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

    // Debugger state flags
    stop_here: bool = false,
    return_here: bool = false,
    step_mode: StepMode = .none,

    pub const StepMode = enum { none, step_into, step_over, step_return };

    /// Continue command (c/cont/continue)
    /// Continues execution until next breakpoint or end
    pub fn do_continue(self: *Self, arg: []const u8) !void {
        _ = arg;
        self.step_mode = .none;
        self.stop_here = false;
        self.return_here = false;
        try self.message("Continuing...");
    }

    /// Step command (s/step)
    /// Executes and stops at the next line (stepping into function calls)
    pub fn do_step(self: *Self, arg: []const u8) !void {
        _ = arg;
        self.step_mode = .step_into;
        self.stop_here = true;
        try self.message("Stepping into...");
    }

    /// Next command (n/next)
    /// Executes and stops at the next line in current function (stepping over calls)
    pub fn do_next(self: *Self, arg: []const u8) !void {
        _ = arg;
        self.step_mode = .step_over;
        self.stop_here = true;
        try self.message("Stepping over...");
    }

    /// Return command (r/return)
    /// Continues execution until the current function returns
    pub fn do_return(self: *Self, arg: []const u8) !void {
        _ = arg;
        self.step_mode = .step_return;
        self.return_here = true;
        try self.message("Continuing until return...");
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
    /// Lists source code around current line (default: 11 lines centered on current)
    pub fn do_list(self: *Self, arg: []const u8) !void {
        if (self.curframe) |frame| {
            // Parse optional line range
            var first: usize = if (frame.lineno > 5) frame.lineno - 5 else 1;
            var last: usize = frame.lineno + 5;

            if (arg.len > 0) {
                // Parse "first" or "first,last"
                if (std.mem.indexOf(u8, arg, ",")) |comma| {
                    first = std.fmt.parseInt(usize, arg[0..comma], 10) catch first;
                    last = std.fmt.parseInt(usize, arg[comma + 1 ..], 10) catch last;
                } else {
                    const line = std.fmt.parseInt(usize, arg, 10) catch frame.lineno;
                    first = if (line > 5) line - 5 else 1;
                    last = line + 5;
                }
            }

            // Read the source file
            const file = std.fs.cwd().openFile(frame.filename, .{}) catch {
                try self.error_msg("Could not open source file");
                return;
            };
            defer file.close();

            const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
                try self.error_msg("Could not read source file");
                return;
            };
            defer self.allocator.free(content);

            // Split into lines and print
            var lines = std.mem.splitScalar(u8, content, '\n');
            var lineno: usize = 0;
            while (lines.next()) |line| {
                lineno += 1;
                if (lineno < first) continue;
                if (lineno > last) break;

                // Mark current line with arrow
                const marker = if (lineno == frame.lineno) "->" else "  ";
                const bp_marker = if (self.hasBreakpoint(frame.filename, lineno)) "B" else " ";
                try self.stdout.print("{s}{s}{d:>4}\t{s}\n", .{ marker, bp_marker, lineno, line });
            }
        } else {
            try self.error_msg("No current frame");
        }
    }

    /// Check if there's a breakpoint at given location
    fn hasBreakpoint(self: *Self, filename: []const u8, lineno: usize) bool {
        for (self.breakpoints.items) |bp| {
            if (bp.enabled and bp.line == lineno and std.mem.eql(u8, bp.file, filename)) {
                return true;
            }
        }
        return false;
    }

    /// Print command (p/print)
    /// Evaluates and prints expression using current frame's locals/globals
    pub fn do_print(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            try self.error_msg("*** No expression given");
            return;
        }

        if (self.curframe) |frame| {
            // Look up in locals first, then globals
            if (frame.locals.get(arg)) |value| {
                try self.stdout.print("{s}\n", .{value});
            } else if (frame.globals.get(arg)) |value| {
                try self.stdout.print("{s}\n", .{value});
            } else {
                // In AOT context, we can't dynamically evaluate expressions
                // Show what we know about the expression
                try self.stdout.print("*** NameError: name '{s}' is not defined\n", .{arg});
                try self.stdout.print("(Note: In AOT mode, only tracked variables can be inspected)\n", .{});
            }
        } else {
            // No frame - just echo (limited functionality)
            try self.stdout.print("{s}\n", .{arg});
        }
    }

    /// Pretty print command (pp)
    pub fn do_pp(self: *Self, arg: []const u8) !void {
        try self.do_print(arg);
    }

    /// Quit command (q/quit/exit)
    /// Exits the debugger, aborting the program
    pub fn do_quit(self: *Self, arg: []const u8) !void {
        _ = arg;
        try self.message("The program finished and will be restarted");
        self.quitting = true;
    }

    // Quit flag
    quitting: bool = false,

    /// Help command (h/help)
    pub fn do_help(self: *Self, arg: []const u8) !void {
        if (arg.len == 0) {
            try self.message("Documented commands (type help <topic>):");
            try self.message("=========================================");
            try self.message("break clear continue down help list next print");
            try self.message("pp quit return step up where");
        } else {
            // Show help for specific command
            if (std.mem.eql(u8, arg, "break") or std.mem.eql(u8, arg, "b")) {
                try self.message("b(reak) [([filename:]lineno | function) [, condition]]");
                try self.message("        With no argument, list all breakpoints.");
                try self.message("        With a line number, set a breakpoint at that line.");
            } else if (std.mem.eql(u8, arg, "clear") or std.mem.eql(u8, arg, "cl")) {
                try self.message("cl(ear) [bpnumber [bpnumber ...]]");
                try self.message("        Clear the specified breakpoints (or all breakpoints).");
            } else if (std.mem.eql(u8, arg, "continue") or std.mem.eql(u8, arg, "c")) {
                try self.message("c(ont(inue))");
                try self.message("        Continue execution, only stop when a breakpoint is encountered.");
            } else if (std.mem.eql(u8, arg, "step") or std.mem.eql(u8, arg, "s")) {
                try self.message("s(tep)");
                try self.message("        Execute the current line, stop at first possible occasion.");
            } else if (std.mem.eql(u8, arg, "next") or std.mem.eql(u8, arg, "n")) {
                try self.message("n(ext)");
                try self.message("        Continue execution until the next line in the current function.");
            } else if (std.mem.eql(u8, arg, "return") or std.mem.eql(u8, arg, "r")) {
                try self.message("r(eturn)");
                try self.message("        Continue execution until the current function returns.");
            } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "l")) {
                try self.message("l(ist) [first[, last]]");
                try self.message("        List source code for the current file.");
            } else if (std.mem.eql(u8, arg, "print") or std.mem.eql(u8, arg, "p")) {
                try self.message("p expression");
                try self.message("        Print the value of the expression.");
            } else if (std.mem.eql(u8, arg, "where") or std.mem.eql(u8, arg, "w") or std.mem.eql(u8, arg, "bt")) {
                try self.message("w(here) / bt");
                try self.message("        Print a stack trace, with the most recent frame at the bottom.");
            } else if (std.mem.eql(u8, arg, "up") or std.mem.eql(u8, arg, "u")) {
                try self.message("u(p) [count]");
                try self.message("        Move the current frame count levels up in the stack trace.");
            } else if (std.mem.eql(u8, arg, "down") or std.mem.eql(u8, arg, "d")) {
                try self.message("d(own) [count]");
                try self.message("        Move the current frame count levels down in the stack trace.");
            } else if (std.mem.eql(u8, arg, "quit") or std.mem.eql(u8, arg, "q")) {
                try self.message("q(uit) / exit");
                try self.message("        Quit from the debugger. The program being executed is aborted.");
            } else {
                try self.stdout.print("*** No help on {s}\n", .{arg});
            }
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
    /// In AOT mode, this loads and displays the script for interactive debugging
    pub fn run(self: *Self, cmd: []const u8) !void {
        // Create initial frame from command
        var frame = Frame.init(self.allocator, "<string>", 1, "<module>");
        try self.stack.append(frame);
        self.curindex = 0;
        self.curframe = &self.stack.items[0];

        try self.message("Starting debugger on command:");
        try self.stdout.print("> {s}\n", .{cmd});

        // Enter interactive mode
        try self.interact();
    }

    /// Start debugging at the call site
    /// Sets up trace infrastructure for AOT debugging
    pub fn setTrace(self: *Self) void {
        self.step_mode = .step_into;
        self.stop_here = true;
        // In AOT context, we mark that debugging is active
        // Generated code should check this flag and call debugger hooks
    }

    /// Post-mortem debugging
    /// Examines the exception traceback
    pub fn postMortem(self: *Self) !void {
        try self.message("Post-mortem debugging");

        // In AOT mode, we enter interactive mode with whatever stack we have
        if (self.stack.items.len == 0) {
            try self.message("(No traceback available)");
        } else {
            try self.message("Traceback (most recent call last):");
            try self.printStack();
        }

        // Enter interactive mode
        try self.interact();
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

// Global debugger instance (thread-local for safety)
threadlocal var global_pdb: ?*Pdb = null;

/// Convenience function to set a breakpoint at the call site
/// Usage: pdb.set_trace()
pub fn set_trace() void {
    // In AOT mode, this is a no-op at runtime
    // The compiled code should check for breakpoints
    // This is a marker for developers to know debugging should start here
    if (global_pdb) |pdb| {
        pdb.setTrace();
    }
}

/// Post-mortem debugging of last exception
/// Usage: pdb.pm()
pub fn pm() void {
    if (global_pdb) |pdb| {
        pdb.postMortem() catch {};
    }
}

/// Run a statement under the debugger
/// Usage: pdb.run(statement, globals, locals)
pub fn run(statement: []const u8, globals: ?*anyopaque, locals: ?*anyopaque) void {
    _ = globals;
    _ = locals;
    // Use heap allocator since we don't have access to one
    const allocator = allocator_helper.fast_allocator;
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();
    global_pdb = &pdb;
    defer {
        global_pdb = null;
    }
    pdb.run(statement) catch {};
}

/// Run a script file under the debugger
/// Usage: pdb.runscript(filename)
pub fn runscript(allocator: std.mem.Allocator, filename: []const u8) !void {
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();
    global_pdb = &pdb;
    defer {
        global_pdb = null;
    }

    // Create frame for the script
    var frame = Frame.init(allocator, filename, 1, "<module>");
    try pdb.stack.append(frame);
    pdb.curindex = 0;
    pdb.curframe = &pdb.stack.items[0];

    try pdb.message("Debugging script:");
    try pdb.stdout.print("> {s}\n", .{filename});

    // Enter interactive mode
    try pdb.interact();
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
