//! CPython source: Lib/pdb.py
//!
//! Provides an interactive debugger for Python programs.
//!
//! Mirrors: CPython Lib/pdb.py
//!
//! Main Pdb class and interactive debugging loop.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const breakpoints_mod = @import("breakpoints.zig");
const commands_mod = @import("commands.zig");
const helpers = @import("helpers.zig");

pub const Breakpoint = types.Breakpoint;
pub const Frame = types.Frame;
pub const BreakpointManager = breakpoints_mod.BreakpointManager;

pub const StepMode = enum { none, step_into, step_over, step_return };

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

    // Debugger state flags
    stop_here: bool,
    return_here: bool,
    step_mode: StepMode,
    quitting: bool,

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
            .stop_here = false,
            .return_here = false,
            .step_mode = .none,
            .quitting = false,
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
        return BreakpointManager.setBreak(&self.breakpoints, &self.bp_counter, filename, lineno, temporary, cond);
    }

    /// Clear a breakpoint by number
    pub fn clearBreak(self: *Self, number: u32) bool {
        return BreakpointManager.clearBreak(&self.breakpoints, number);
    }

    /// Clear all breakpoints
    pub fn clearAllBreaks(self: *Self) void {
        BreakpointManager.clearAllBreaks(&self.breakpoints);
    }

    /// Get breakpoint by number
    pub fn getBreak(self: *Self, number: u32) ?*Breakpoint {
        return BreakpointManager.getBreak(&self.breakpoints, number);
    }

    /// Get all breakpoints at a location
    pub fn getBreaks(self: *Self, filename: []const u8, lineno: usize) []Breakpoint {
        return BreakpointManager.getBreaks(&self.breakpoints, self.allocator, filename, lineno);
    }

    // ========================================================================
    // Debugger Commands
    // ========================================================================

    /// Break command (b/break)
    pub fn do_break(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_break(self.allocator, &self.breakpoints, &self.bp_counter, self.stdout, arg);
    }

    /// Clear command (cl/clear)
    pub fn do_clear(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_clear(&self.breakpoints, self.stdout, arg);
    }

    /// Continue command (c/cont/continue)
    pub fn do_continue(self: *Self, arg: []const u8) !void {
        self.step_mode = .none;
        self.stop_here = false;
        self.return_here = false;
        try commands_mod.Commands.do_continue(self.stdout, arg);
    }

    /// Step command (s/step)
    pub fn do_step(self: *Self, arg: []const u8) !void {
        self.step_mode = .step_into;
        self.stop_here = true;
        try commands_mod.Commands.do_step(self.stdout, arg);
    }

    /// Next command (n/next)
    pub fn do_next(self: *Self, arg: []const u8) !void {
        self.step_mode = .step_over;
        self.stop_here = true;
        try commands_mod.Commands.do_next(self.stdout, arg);
    }

    /// Return command (r/return)
    pub fn do_return(self: *Self, arg: []const u8) !void {
        self.step_mode = .step_return;
        self.return_here = true;
        try commands_mod.Commands.do_return(self.stdout, arg);
    }

    /// Where command (w/where/bt)
    pub fn do_where(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_where(&self.stack, self.curindex, self.stdout, arg);
    }

    /// Up command (u/up)
    pub fn do_up(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_up(&self.stack, &self.curindex, &self.curframe, self.stdout, arg);
    }

    /// Down command (d/down)
    pub fn do_down(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_down(&self.stack, &self.curindex, &self.curframe, self.stdout, arg);
    }

    /// List command (l/list)
    pub fn do_list(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_list(self.allocator, &self.breakpoints, self.curframe, self.stdout, arg);
    }

    /// Print command (p/print)
    pub fn do_print(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_print(self.curframe, self.stdout, arg);
    }

    /// Pretty print command (pp)
    pub fn do_pp(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_pp(self.curframe, self.stdout, arg);
    }

    /// Quit command (q/quit/exit)
    pub fn do_quit(self: *Self, arg: []const u8) !void {
        self.quitting = true;
        try commands_mod.Commands.do_quit(self.stdout, arg);
    }

    /// Help command (h/help)
    pub fn do_help(self: *Self, arg: []const u8) !void {
        try commands_mod.Commands.do_help(self.stdout, arg);
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    pub fn message(self: *Self, msg: []const u8) !void {
        try helpers.message(self.stdout, msg);
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
            try helpers.printStack(&self.stack, self.curindex, self.stdout);
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
// Tests
// ============================================================================

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
