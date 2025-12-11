//! Debugger commands for the Python debugger
//!
//! Implements all interactive debugger commands (break, continue, step, etc.)

const std = @import("std");
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const breakpoints_mod = @import("breakpoints.zig");
const Breakpoint = types.Breakpoint;
const Frame = types.Frame;

/// Debugger commands implementation
pub const Commands = struct {
    /// Break command (b/break)
    pub fn do_break(
        allocator: std.mem.Allocator,
        breakpoints: *std.ArrayList(Breakpoint),
        bp_counter: *u32,
        writer: anytype,
        arg: []const u8,
    ) !void {
        if (arg.len == 0) {
            // List all breakpoints
            if (breakpoints.items.len == 0) {
                try helpers.message(writer, "No breakpoints.");
                return;
            }
            try helpers.message(writer, "Num Type         Disp Enb   Where");
            for (breakpoints.items) |*bp| {
                const formatted = try bp.bpformat(allocator);
                defer allocator.free(formatted);
                try helpers.message(writer, formatted);
            }
        } else {
            // Parse location
            const parsed = helpers.parseBreakArg(arg);
            const number = try breakpoints_mod.BreakpointManager.setBreak(
                breakpoints,
                bp_counter,
                parsed.filename,
                parsed.lineno,
                false,
                parsed.condition,
            );
            try writer.print("Breakpoint {d} at {s}:{d}\n", .{ number, parsed.filename, parsed.lineno });
        }
    }

    /// Clear command (cl/clear)
    pub fn do_clear(
        breakpoints: *std.ArrayList(Breakpoint),
        writer: anytype,
        arg: []const u8,
    ) !void {
        if (arg.len == 0) {
            breakpoints_mod.BreakpointManager.clearAllBreaks(breakpoints);
            try helpers.message(writer, "Cleared all breakpoints.");
        } else {
            const number = std.fmt.parseInt(u32, arg, 10) catch {
                try helpers.error_msg(writer, "Invalid breakpoint number");
                return;
            };
            if (breakpoints_mod.BreakpointManager.clearBreak(breakpoints, number)) {
                try writer.print("Deleted breakpoint {d}\n", .{number});
            } else {
                try writer.print("No breakpoint numbered {d}\n", .{number});
            }
        }
    }

    /// Continue command (c/cont/continue)
    /// Continues execution until next breakpoint or end
    pub fn do_continue(writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.message(writer, "Continuing...");
    }

    /// Step command (s/step)
    /// Executes and stops at the next line (stepping into function calls)
    pub fn do_step(writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.message(writer, "Stepping into...");
    }

    /// Next command (n/next)
    /// Executes and stops at the next line in current function (stepping over calls)
    pub fn do_next(writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.message(writer, "Stepping over...");
    }

    /// Return command (r/return)
    /// Continues execution until the current function returns
    pub fn do_return(writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.message(writer, "Continuing until return...");
    }

    /// Where command (w/where/bt)
    pub fn do_where(stack: *std.ArrayList(Frame), curindex: usize, writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.printStack(stack, curindex, writer);
    }

    /// Up command (u/up)
    pub fn do_up(
        stack: *std.ArrayList(Frame),
        curindex: *usize,
        curframe: *?*Frame,
        writer: anytype,
        arg: []const u8,
    ) !void {
        const count = if (arg.len > 0)
            std.fmt.parseInt(usize, arg, 10) catch 1
        else
            1;

        if (curindex.* >= count) {
            curindex.* -= count;
            curframe.* = &stack.items[curindex.*];
            try helpers.printFrameInfo(curframe.*, writer);
        } else {
            try helpers.error_msg(writer, "Oldest frame");
        }
    }

    /// Down command (d/down)
    pub fn do_down(
        stack: *std.ArrayList(Frame),
        curindex: *usize,
        curframe: *?*Frame,
        writer: anytype,
        arg: []const u8,
    ) !void {
        const count = if (arg.len > 0)
            std.fmt.parseInt(usize, arg, 10) catch 1
        else
            1;

        if (curindex.* + count < stack.items.len) {
            curindex.* += count;
            curframe.* = &stack.items[curindex.*];
            try helpers.printFrameInfo(curframe.*, writer);
        } else {
            try helpers.error_msg(writer, "Newest frame");
        }
    }

    /// List command (l/list)
    /// Lists source code around current line (default: 11 lines centered on current)
    pub fn do_list(
        allocator: std.mem.Allocator,
        breakpoints: *std.ArrayList(Breakpoint),
        curframe: ?*Frame,
        writer: anytype,
        arg: []const u8,
    ) !void {
        if (curframe) |frame| {
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
                try helpers.error_msg(writer, "Could not open source file");
                return;
            };
            defer file.close();

            const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
                try helpers.error_msg(writer, "Could not read source file");
                return;
            };
            defer allocator.free(content);

            // Split into lines and print
            var lines = std.mem.splitScalar(u8, content, '\n');
            var lineno: usize = 0;
            while (lines.next()) |line| {
                lineno += 1;
                if (lineno < first) continue;
                if (lineno > last) break;

                // Mark current line with arrow
                const marker = if (lineno == frame.lineno) "->" else "  ";
                const bp_marker = if (breakpoints_mod.BreakpointManager.hasBreakpoint(
                    breakpoints,
                    frame.filename,
                    lineno,
                )) "B" else " ";
                try writer.print("{s}{s}{d:>4}\t{s}\n", .{ marker, bp_marker, lineno, line });
            }
        } else {
            try helpers.error_msg(writer, "No current frame");
        }
    }

    /// Print command (p/print)
    /// Evaluates and prints expression using current frame's locals/globals
    pub fn do_print(
        curframe: ?*Frame,
        writer: anytype,
        arg: []const u8,
    ) !void {
        if (arg.len == 0) {
            try helpers.error_msg(writer, "*** No expression given");
            return;
        }

        if (curframe) |frame| {
            // Look up in locals first, then globals
            if (frame.locals.get(arg)) |value| {
                try writer.print("{s}\n", .{value});
            } else if (frame.globals.get(arg)) |value| {
                try writer.print("{s}\n", .{value});
            } else {
                // In AOT context, we can't dynamically evaluate expressions
                // Show what we know about the expression
                try writer.print("*** NameError: name '{s}' is not defined\n", .{arg});
                try writer.print("(Note: In AOT mode, only tracked variables can be inspected)\n", .{});
            }
        } else {
            // No frame - just echo (limited functionality)
            try writer.print("{s}\n", .{arg});
        }
    }

    /// Pretty print command (pp)
    pub fn do_pp(
        curframe: ?*Frame,
        writer: anytype,
        arg: []const u8,
    ) !void {
        try do_print(curframe, writer, arg);
    }

    /// Quit command (q/quit/exit)
    /// Exits the debugger, aborting the program
    pub fn do_quit(writer: anytype, arg: []const u8) !void {
        _ = arg;
        try helpers.message(writer, "The program finished and will be restarted");
    }

    /// Help command (h/help)
    pub fn do_help(writer: anytype, arg: []const u8) !void {
        if (arg.len == 0) {
            try helpers.message(writer, "Documented commands (type help <topic>):");
            try helpers.message(writer, "=========================================");
            try helpers.message(writer, "break clear continue down help list next print");
            try helpers.message(writer, "pp quit return step up where");
        } else {
            // Show help for specific command
            if (std.mem.eql(u8, arg, "break") or std.mem.eql(u8, arg, "b")) {
                try helpers.message(writer, "b(reak) [([filename:]lineno | function) [, condition]]");
                try helpers.message(writer, "        With no argument, list all breakpoints.");
                try helpers.message(writer, "        With a line number, set a breakpoint at that line.");
            } else if (std.mem.eql(u8, arg, "clear") or std.mem.eql(u8, arg, "cl")) {
                try helpers.message(writer, "cl(ear) [bpnumber [bpnumber ...]]");
                try helpers.message(writer, "        Clear the specified breakpoints (or all breakpoints).");
            } else if (std.mem.eql(u8, arg, "continue") or std.mem.eql(u8, arg, "c")) {
                try helpers.message(writer, "c(ont(inue))");
                try helpers.message(writer, "        Continue execution, only stop when a breakpoint is encountered.");
            } else if (std.mem.eql(u8, arg, "step") or std.mem.eql(u8, arg, "s")) {
                try helpers.message(writer, "s(tep)");
                try helpers.message(writer, "        Execute the current line, stop at first possible occasion.");
            } else if (std.mem.eql(u8, arg, "next") or std.mem.eql(u8, arg, "n")) {
                try helpers.message(writer, "n(ext)");
                try helpers.message(writer, "        Continue execution until the next line in the current function.");
            } else if (std.mem.eql(u8, arg, "return") or std.mem.eql(u8, arg, "r")) {
                try helpers.message(writer, "r(eturn)");
                try helpers.message(writer, "        Continue execution until the current function returns.");
            } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "l")) {
                try helpers.message(writer, "l(ist) [first[, last]]");
                try helpers.message(writer, "        List source code for the current file.");
            } else if (std.mem.eql(u8, arg, "print") or std.mem.eql(u8, arg, "p")) {
                try helpers.message(writer, "p expression");
                try helpers.message(writer, "        Print the value of the expression.");
            } else if (std.mem.eql(u8, arg, "where") or std.mem.eql(u8, arg, "w") or std.mem.eql(u8, arg, "bt")) {
                try helpers.message(writer, "w(here) / bt");
                try helpers.message(writer, "        Print a stack trace, with the most recent frame at the bottom.");
            } else if (std.mem.eql(u8, arg, "up") or std.mem.eql(u8, arg, "u")) {
                try helpers.message(writer, "u(p) [count]");
                try helpers.message(writer, "        Move the current frame count levels up in the stack trace.");
            } else if (std.mem.eql(u8, arg, "down") or std.mem.eql(u8, arg, "d")) {
                try helpers.message(writer, "d(own) [count]");
                try helpers.message(writer, "        Move the current frame count levels down in the stack trace.");
            } else if (std.mem.eql(u8, arg, "quit") or std.mem.eql(u8, arg, "q")) {
                try helpers.message(writer, "q(uit) / exit");
                try helpers.message(writer, "        Quit from the debugger. The program being executed is aborted.");
            } else {
                try writer.print("*** No help on {s}\n", .{arg});
            }
        }
    }
};
