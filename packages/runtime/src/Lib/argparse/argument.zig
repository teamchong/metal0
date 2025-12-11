//! Argument definition and methods
//!
//! Defines the Argument struct which represents a single command-line argument.

const std = @import("std");
const types = @import("types.zig");

/// Definition of a command-line argument
pub const Argument = struct {
    const Self = @This();

    // Names (short and/or long)
    names: []const []const u8,

    // Configuration
    action: types.Action = .store,
    nargs: ?types.Nargs = null,
    const_value: ?[]const u8 = null,
    default: ?[]const u8 = null,
    type_name: []const u8 = "string",
    choices: ?[]const []const u8 = null,
    required: bool = false,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    dest: ?[]const u8 = null,

    /// Check if this is a positional argument
    pub fn isPositional(self: Self) bool {
        if (self.names.len == 0) return true;
        return !std.mem.startsWith(u8, self.names[0], "-");
    }

    /// Get the destination name for this argument
    pub fn getDest(self: Self) []const u8 {
        if (self.dest) |d| return d;
        if (self.names.len == 0) return "";

        // Find the long option name, or use the first one
        for (self.names) |name| {
            if (std.mem.startsWith(u8, name, "--")) {
                return name[2..];
            }
        }

        // Use short option without dash
        if (std.mem.startsWith(u8, self.names[0], "-")) {
            return self.names[0][1..];
        }

        return self.names[0];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Argument.getDest" {
    const arg1 = Argument{
        .names = &.{ "-v", "--verbose" },
    };
    try std.testing.expectEqualStrings("verbose", arg1.getDest());

    const arg2 = Argument{
        .names = &.{"-n"},
    };
    try std.testing.expectEqualStrings("n", arg2.getDest());

    const arg3 = Argument{
        .names = &.{"filename"},
    };
    try std.testing.expectEqualStrings("filename", arg3.getDest());

    const arg4 = Argument{
        .names = &.{"-x"},
        .dest = "custom_dest",
    };
    try std.testing.expectEqualStrings("custom_dest", arg4.getDest());
}

test "Argument.isPositional" {
    const pos = Argument{ .names = &.{"filename"} };
    try std.testing.expect(pos.isPositional());

    const opt = Argument{ .names = &.{"--file"} };
    try std.testing.expect(!opt.isPositional());

    const short = Argument{ .names = &.{"-f"} };
    try std.testing.expect(!short.isPositional());
}
