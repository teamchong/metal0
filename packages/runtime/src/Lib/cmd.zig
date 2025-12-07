//! CPython source: Lib/cmd.py
//!
//! Provides a simple framework for writing line-oriented command interpreters.
//!
//! Mirrors: CPython Lib/cmd.py

const std = @import("std");

// ============================================================================
// Cmd - Command Interpreter
// ============================================================================

/// Generic framework for command line interpreters
pub fn Cmd(comptime Context: type) type {
    return struct {
        const Self = @This();

        // Configuration
        prompt: []const u8,
        identchars: []const u8,
        ruler: u8,
        lastcmd: []const u8,
        intro: ?[]const u8,
        doc_leader: []const u8,
        doc_header: []const u8,
        misc_header: []const u8,
        undoc_header: []const u8,
        nohelp: []const u8,
        use_rawinput: bool,

        // State
        cmdqueue: std.ArrayList([]const u8),
        allocator: std.mem.Allocator,
        context: ?*Context,
        stop: bool,

        // Stdin/Stdout
        stdin: std.fs.File.Reader,
        stdout: std.fs.File.Writer,

        pub fn init(allocator: std.mem.Allocator, context: ?*Context) Self {
            return .{
                .prompt = "(Cmd) ",
                .identchars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
                .ruler = '=',
                .lastcmd = "",
                .intro = null,
                .doc_leader = "",
                .doc_header = "Documented commands (type help <topic>):",
                .misc_header = "Miscellaneous help topics:",
                .undoc_header = "Undocumented commands:",
                .nohelp = "*** No help on %s",
                .use_rawinput = true,
                .cmdqueue = std.ArrayList([]const u8).init(allocator),
                .allocator = allocator,
                .context = context,
                .stop = false,
                .stdin = std.io.getStdIn().reader(),
                .stdout = std.io.getStdOut().writer(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.cmdqueue.deinit();
        }

        /// Main command loop
        pub fn cmdloop(self: *Self, intro: ?[]const u8) !void {
            self.stop = false;

            // Print intro if provided
            if (intro orelse self.intro) |i| {
                try self.stdout.print("{s}\n", .{i});
            }

            while (!self.stop) {
                var line: ?[]const u8 = null;

                // Check command queue first
                if (self.cmdqueue.items.len > 0) {
                    line = self.cmdqueue.orderedRemove(0);
                } else {
                    // Read from stdin
                    try self.stdout.print("{s}", .{self.prompt});
                    var buf: [1024]u8 = undefined;
                    const read = try self.stdin.readUntilDelimiterOrEof(&buf, '\n');
                    if (read) |l| {
                        line = l;
                    } else {
                        line = "EOF";
                    }
                }

                if (line) |l| {
                    try self.onecmd(l);
                }
            }
        }

        /// Execute a single command
        pub fn onecmd(self: *Self, line: []const u8) !void {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            if (trimmed.len == 0) {
                return self.emptyline();
            }

            // Parse command and arguments
            const parsed = parseline(trimmed);
            const cmd = parsed.cmd;
            const args = parsed.args;

            if (cmd) |c| {
                self.lastcmd = trimmed;

                // Try to dispatch
                if (std.mem.eql(u8, c, "help")) {
                    try self.do_help(args);
                } else if (std.mem.eql(u8, c, "quit") or std.mem.eql(u8, c, "exit") or std.mem.eql(u8, c, "EOF")) {
                    self.stop = true;
                } else {
                    try self.default(trimmed);
                }
            } else {
                try self.default(trimmed);
            }
        }

        /// Parse a line into command and arguments
        pub fn parseline(line: []const u8) struct { cmd: ?[]const u8, args: []const u8 } {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) {
                return .{ .cmd = null, .args = "" };
            }

            // Find first space
            var i: usize = 0;
            while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != '\t') : (i += 1) {}

            const cmd = trimmed[0..i];
            const args = if (i < trimmed.len) std.mem.trim(u8, trimmed[i..], " \t") else "";

            return .{ .cmd = cmd, .args = args };
        }

        /// Handle empty line (default: repeat last command)
        pub fn emptyline(self: *Self) void {
            if (self.lastcmd.len > 0) {
                self.onecmd(self.lastcmd) catch {};
            }
        }

        /// Handle unknown command
        pub fn default(self: *Self, line: []const u8) !void {
            try self.stdout.print("*** Unknown syntax: {s}\n", .{line});
        }

        /// Help command
        pub fn do_help(self: *Self, arg: []const u8) !void {
            if (arg.len == 0) {
                try self.stdout.writeAll("Type 'help <command>' for help on a specific command.\n");
                try self.stdout.writeAll("Available commands: help, quit, exit\n");
            } else if (std.mem.eql(u8, arg, "help")) {
                try self.stdout.writeAll("Display help information.\n");
            } else if (std.mem.eql(u8, arg, "quit") or std.mem.eql(u8, arg, "exit")) {
                try self.stdout.writeAll("Exit the interpreter.\n");
            } else {
                try self.stdout.print("*** No help on {s}\n", .{arg});
            }
        }

        /// Print a column-aligned list of strings
        pub fn columnize(self: *Self, list: []const []const u8, displaywidth: usize) !void {
            if (list.len == 0) return;

            // Find max width
            var maxwidth: usize = 0;
            for (list) |item| {
                if (item.len > maxwidth) maxwidth = item.len;
            }
            maxwidth += 2;

            const ncols = @max(1, displaywidth / maxwidth);
            const nrows = (list.len + ncols - 1) / ncols;

            var row: usize = 0;
            while (row < nrows) : (row += 1) {
                var col: usize = 0;
                while (col < ncols) : (col += 1) {
                    const idx = col * nrows + row;
                    if (idx < list.len) {
                        const item = list[idx];
                        try self.stdout.print("{s}", .{item});
                        if (col < ncols - 1) {
                            var padding = maxwidth - item.len;
                            while (padding > 0) : (padding -= 1) {
                                try self.stdout.writeByte(' ');
                            }
                        }
                    }
                }
                try self.stdout.writeByte('\n');
            }
        }

        /// Pre-command hook
        pub fn precmd(self: *Self, line: []const u8) []const u8 {
            _ = self;
            return line;
        }

        /// Post-command hook
        pub fn postcmd(self: *Self, stop: bool, line: []const u8) bool {
            _ = self;
            _ = line;
            return stop;
        }

        /// Pre-loop hook
        pub fn preloop(self: *Self) void {
            _ = self;
        }

        /// Post-loop hook
        pub fn postloop(self: *Self) void {
            _ = self;
        }

        /// Complete a command (for readline integration)
        pub fn complete(self: *Self, text: []const u8, state: usize) ?[]const u8 {
            _ = self;
            _ = text;
            _ = state;
            return null;
        }

        /// Get possible completions
        pub fn completenames(self: *Self, text: []const u8) ![][]const u8 {
            _ = self;
            _ = text;
            return &[_][]const u8{};
        }

        /// Complete default (filenames)
        pub fn completedefault(self: *Self, text: []const u8, line: []const u8, begidx: usize, endidx: usize) ![][]const u8 {
            _ = self;
            _ = text;
            _ = line;
            _ = begidx;
            _ = endidx;
            return &[_][]const u8{};
        }
    };
}

// ============================================================================
// Simple Cmd without Context
// ============================================================================

/// Simple command interpreter without context
pub const SimpleCmd = Cmd(void);

// ============================================================================
// Tests
// ============================================================================

test "Cmd init" {
    const allocator = std.testing.allocator;
    var cmd = SimpleCmd.init(allocator, null);
    defer cmd.deinit();

    try std.testing.expectEqualStrings("(Cmd) ", cmd.prompt);
    try std.testing.expect(!cmd.stop);
}

test "parseline" {
    const result1 = SimpleCmd.parseline("help topic");
    try std.testing.expectEqualStrings("help", result1.cmd.?);
    try std.testing.expectEqualStrings("topic", result1.args);

    const result2 = SimpleCmd.parseline("quit");
    try std.testing.expectEqualStrings("quit", result2.cmd.?);
    try std.testing.expectEqualStrings("", result2.args);

    const result3 = SimpleCmd.parseline("");
    try std.testing.expect(result3.cmd == null);
}

test "parseline with extra spaces" {
    const result = SimpleCmd.parseline("  help   topic  ");
    try std.testing.expectEqualStrings("help", result.cmd.?);
    try std.testing.expectEqualStrings("topic", result.args);
}
