/// Common utilities for CLI commands
/// ANSI colors and print helpers
const std = @import("std");

// ANSI color codes for terminal UX
pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const red = "\x1b[31m";
    pub const cyan = "\x1b[36m";
    pub const bold_cyan = "\x1b[1;36m";
    pub const bold_green = "\x1b[1;32m";
    pub const bold_yellow = "\x1b[1;33m";
    pub const bold_red = "\x1b[1;31m";
};

pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}✓{s} ", .{ Color.bold_green, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}✗{s} ", .{ Color.bold_red, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

pub fn printInfo(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}→{s} ", .{ Color.bold_cyan, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

pub fn printWarn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}!{s} ", .{ Color.bold_yellow, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}
