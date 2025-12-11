//! CPython source: Lib/optparse.py
//!
//! Represents a command-line option.
//! Mirrors: CPython Lib/optparse.py

const std = @import("std");
const types = @import("types.zig");
const values = @import("values.zig");

const OptionAction = types.OptionAction;
const OptionType = types.OptionType;
const Values = values.Values;

// Forward declaration for callback
pub const OptionParser = opaque {};

/// Represents a command-line option
pub const Option = struct {
    const Self = @This();

    // Option strings (e.g., "-f", "--file")
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,

    // Configuration
    action: OptionAction = .store,
    option_type: OptionType = .string,
    dest: ?[]const u8 = null,
    default: ?[]const u8 = null,
    const_value: ?[]const u8 = null,
    nargs: usize = 1,
    choices: ?[]const []const u8 = null,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    callback: ?*const fn (*OptionParser, *Option, []const u8, *Values) void = null,

    /// Create an option
    pub fn init(short: ?[]const u8, long: ?[]const u8) Self {
        return .{
            .short = short,
            .long = long,
        };
    }

    /// Get the destination name
    pub fn getDest(self: Self) []const u8 {
        if (self.dest) |d| return d;

        // Derive from long option
        if (self.long) |l| {
            if (std.mem.startsWith(u8, l, "--")) {
                return l[2..];
            }
        }

        // Derive from short option
        if (self.short) |s| {
            if (std.mem.startsWith(u8, s, "-")) {
                return s[1..];
            }
        }

        return "";
    }

    /// Check if a string matches this option
    pub fn matches(self: Self, arg: []const u8) bool {
        if (self.short) |s| {
            if (std.mem.eql(u8, arg, s)) return true;
        }
        if (self.long) |l| {
            if (std.mem.eql(u8, arg, l)) return true;
            // Check for --opt=value format
            if (std.mem.startsWith(u8, arg, l) and
                arg.len > l.len and arg[l.len] == '=')
            {
                return true;
            }
        }
        return false;
    }

    /// Get metavar for help display
    pub fn getMetavar(self: Self) []const u8 {
        if (self.metavar) |m| return m;
        if (self.choices) |_| return "CHOICE";

        return switch (self.option_type) {
            .string => "STRING",
            .int, .long => "INT",
            .float => "FLOAT",
            .complex => "COMPLEX",
            .choice => "CHOICE",
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Option init" {
    const opt = Option.init("-v", "--verbose");
    try std.testing.expectEqualStrings("-v", opt.short.?);
    try std.testing.expectEqualStrings("--verbose", opt.long.?);
}

test "Option getDest" {
    const opt1 = Option.init("-v", "--verbose");
    try std.testing.expectEqualStrings("verbose", opt1.getDest());

    const opt2 = Option.init("-n", null);
    try std.testing.expectEqualStrings("n", opt2.getDest());

    var opt3 = Option.init("-x", "--extra");
    opt3.dest = "custom";
    try std.testing.expectEqualStrings("custom", opt3.getDest());
}

test "Option matches" {
    const opt = Option.init("-v", "--verbose");
    try std.testing.expect(opt.matches("-v"));
    try std.testing.expect(opt.matches("--verbose"));
    try std.testing.expect(opt.matches("--verbose=yes"));
    try std.testing.expect(!opt.matches("-x"));
}
