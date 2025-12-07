/// getopt - Command Line Option Parsing
/// Mirrors cpython/Python/getopt.c
///
/// This module provides getopt-style command line parsing:
/// - Short options (-x, -xyz)
/// - Long options (--option, --option=value)
/// - Option arguments (-x value, --option value)

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const GetoptError = error{
    InvalidOption,
    MissingArgument,
    AmbiguousOption,
};

// ============================================================================
// Option Specification
// ============================================================================

/// Option specification for short options
/// Character followed by ':' means option takes an argument
/// Example: "hvf:" means -h, -v, -f <arg>
pub const ShortOpts = []const u8;

/// Long option specification
pub const LongOption = struct {
    name: []const u8,
    has_arg: HasArg = .no,
    flag: ?*i32 = null,
    val: i32 = 0,

    pub const HasArg = enum(u8) {
        no = 0,
        required = 1,
        optional = 2,
    };
};

// ============================================================================
// Parse Result
// ============================================================================

pub const ParsedOption = struct {
    /// The option character or val from long option
    opt: i32,
    /// Argument if any
    arg: ?[]const u8 = null,
    /// Was this a long option?
    is_long: bool = false,
    /// Original option string (for error messages)
    name: []const u8 = "",
};

// ============================================================================
// Getopt State
// ============================================================================

pub const Getopt = struct {
    args: []const []const u8,
    short_opts: []const u8,
    long_opts: []const LongOption = &.{},
    optind: usize = 1, // Current argument index
    optarg: ?[]const u8 = null, // Current option argument
    optopt: i32 = 0, // Last option character
    opterr: bool = true, // Print error messages
    optpos: usize = 0, // Position within combined short opts

    const Self = @This();

    /// Initialize getopt state
    pub fn init(args: []const []const u8, short_opts: []const u8) Self {
        return .{
            .args = args,
            .short_opts = short_opts,
        };
    }

    /// Initialize with long options
    pub fn initLong(
        args: []const []const u8,
        short_opts: []const u8,
        long_opts: []const LongOption,
    ) Self {
        return .{
            .args = args,
            .short_opts = short_opts,
            .long_opts = long_opts,
        };
    }

    /// Get next option
    pub fn next(self: *Self) ?ParsedOption {
        // Skip program name if at start
        if (self.optind == 0) {
            self.optind = 1;
        }

        while (self.optind < self.args.len) {
            const arg = self.args[self.optind];

            // Not an option
            if (arg.len == 0 or arg[0] != '-') {
                self.optind += 1;
                continue;
            }

            // "--" terminates options
            if (std.mem.eql(u8, arg, "--")) {
                self.optind += 1;
                return null;
            }

            // Long option
            if (arg.len > 1 and arg[1] == '-') {
                return self.parseLongOption(arg);
            }

            // Short option
            return self.parseShortOption(arg);
        }

        return null;
    }

    /// Parse a short option like -x or -xyz
    fn parseShortOption(self: *Self, arg: []const u8) ?ParsedOption {
        // Get current position in option string
        if (self.optpos == 0) {
            self.optpos = 1; // Skip '-'
        }

        if (self.optpos >= arg.len) {
            self.optind += 1;
            self.optpos = 0;
            return self.next();
        }

        const c = arg[self.optpos];
        self.optpos += 1;
        self.optopt = c;

        // Find in short_opts
        const idx = std.mem.indexOfScalar(u8, self.short_opts, c);
        if (idx == null) {
            // Unknown option
            if (self.optpos >= arg.len) {
                self.optind += 1;
                self.optpos = 0;
            }
            return .{
                .opt = '?',
                .name = arg[self.optpos - 1 .. self.optpos],
            };
        }

        // Check if takes argument
        const takes_arg = idx.? + 1 < self.short_opts.len and self.short_opts[idx.? + 1] == ':';

        if (takes_arg) {
            // Rest of current arg is the argument
            if (self.optpos < arg.len) {
                self.optarg = arg[self.optpos..];
                self.optind += 1;
                self.optpos = 0;
                return .{
                    .opt = c,
                    .arg = self.optarg,
                    .name = arg[self.optpos - 1 .. self.optpos],
                };
            }

            // Next arg is the argument
            self.optind += 1;
            self.optpos = 0;

            if (self.optind >= self.args.len) {
                // Missing argument
                return .{
                    .opt = ':',
                    .name = &[_]u8{c},
                };
            }

            self.optarg = self.args[self.optind];
            self.optind += 1;
            return .{
                .opt = c,
                .arg = self.optarg,
                .name = &[_]u8{c},
            };
        }

        // No argument
        if (self.optpos >= arg.len) {
            self.optind += 1;
            self.optpos = 0;
        }

        return .{
            .opt = c,
            .name = &[_]u8{c},
        };
    }

    /// Parse a long option like --option or --option=value
    fn parseLongOption(self: *Self, arg: []const u8) ?ParsedOption {
        // Skip "--"
        const opt_start = arg[2..];

        // Find '=' for value
        const eq_pos = std.mem.indexOfScalar(u8, opt_start, '=');
        const name = if (eq_pos) |pos| opt_start[0..pos] else opt_start;

        // Find matching long option
        var match: ?*const LongOption = null;
        var ambiguous = false;

        for (self.long_opts) |*opt| {
            if (std.mem.startsWith(u8, opt.name, name)) {
                if (opt.name.len == name.len) {
                    // Exact match
                    match = opt;
                    ambiguous = false;
                    break;
                } else if (match != null) {
                    // Multiple prefix matches
                    ambiguous = true;
                } else {
                    match = opt;
                }
            }
        }

        self.optind += 1;

        if (ambiguous) {
            return .{
                .opt = '?',
                .is_long = true,
                .name = name,
            };
        }

        if (match == null) {
            return .{
                .opt = '?',
                .is_long = true,
                .name = name,
            };
        }

        const opt = match.?;

        // Handle argument
        if (opt.has_arg == .no) {
            if (eq_pos != null) {
                // Got argument but doesn't take one
                return .{
                    .opt = '?',
                    .is_long = true,
                    .name = opt.name,
                };
            }
            self.optarg = null;
        } else if (opt.has_arg == .required) {
            if (eq_pos) |pos| {
                self.optarg = opt_start[pos + 1 ..];
            } else if (self.optind < self.args.len) {
                self.optarg = self.args[self.optind];
                self.optind += 1;
            } else {
                // Missing required argument
                return .{
                    .opt = ':',
                    .is_long = true,
                    .name = opt.name,
                };
            }
        } else {
            // Optional argument
            if (eq_pos) |pos| {
                self.optarg = opt_start[pos + 1 ..];
            } else {
                self.optarg = null;
            }
        }

        // Set flag if provided
        if (opt.flag) |flag| {
            flag.* = opt.val;
            return .{
                .opt = 0,
                .arg = self.optarg,
                .is_long = true,
                .name = opt.name,
            };
        }

        return .{
            .opt = opt.val,
            .arg = self.optarg,
            .is_long = true,
            .name = opt.name,
        };
    }

    /// Get remaining non-option arguments
    pub fn remaining(self: Self) []const []const u8 {
        if (self.optind >= self.args.len) {
            return &.{};
        }
        return self.args[self.optind..];
    }

    /// Reset to initial state
    pub fn reset(self: *Self) void {
        self.optind = 1;
        self.optpos = 0;
        self.optarg = null;
        self.optopt = 0;
    }
};

// ============================================================================
// Simple Interface
// ============================================================================

/// Simple getopt for basic use cases
pub fn getopt(
    args: []const []const u8,
    optstring: []const u8,
) Getopt {
    return Getopt.init(args, optstring);
}

/// Getopt with long options
pub fn getoptLong(
    args: []const []const u8,
    short_opts: []const u8,
    long_opts: []const LongOption,
) Getopt {
    return Getopt.initLong(args, short_opts, long_opts);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "short options" {
    const args = [_][]const u8{ "prog", "-a", "-b", "-c" };
    var g = Getopt.init(&args, "abc");

    const opt1 = g.next();
    try std.testing.expect(opt1 != null);
    try std.testing.expectEqual(@as(i32, 'a'), opt1.?.opt);

    const opt2 = g.next();
    try std.testing.expect(opt2 != null);
    try std.testing.expectEqual(@as(i32, 'b'), opt2.?.opt);

    const opt3 = g.next();
    try std.testing.expect(opt3 != null);
    try std.testing.expectEqual(@as(i32, 'c'), opt3.?.opt);

    try std.testing.expect(g.next() == null);
}

test "combined short options" {
    const args = [_][]const u8{ "prog", "-abc" };
    var g = Getopt.init(&args, "abc");

    try std.testing.expectEqual(@as(i32, 'a'), g.next().?.opt);
    try std.testing.expectEqual(@as(i32, 'b'), g.next().?.opt);
    try std.testing.expectEqual(@as(i32, 'c'), g.next().?.opt);
    try std.testing.expect(g.next() == null);
}

test "option with argument" {
    const args = [_][]const u8{ "prog", "-f", "file.txt" };
    var g = Getopt.init(&args, "f:");

    const opt = g.next();
    try std.testing.expect(opt != null);
    try std.testing.expectEqual(@as(i32, 'f'), opt.?.opt);
    try std.testing.expectEqualStrings("file.txt", opt.?.arg.?);
}

test "option with attached argument" {
    const args = [_][]const u8{ "prog", "-ffile.txt" };
    var g = Getopt.init(&args, "f:");

    const opt = g.next();
    try std.testing.expect(opt != null);
    try std.testing.expectEqual(@as(i32, 'f'), opt.?.opt);
    try std.testing.expectEqualStrings("file.txt", opt.?.arg.?);
}

test "long options" {
    const long_opts = [_]LongOption{
        .{ .name = "help", .val = 'h' },
        .{ .name = "version", .val = 'v' },
        .{ .name = "file", .has_arg = .required, .val = 'f' },
    };

    const args = [_][]const u8{ "prog", "--help", "--file", "test.txt" };
    var g = Getopt.initLong(&args, "hvf:", &long_opts);

    const opt1 = g.next();
    try std.testing.expect(opt1 != null);
    try std.testing.expectEqual(@as(i32, 'h'), opt1.?.opt);
    try std.testing.expect(opt1.?.is_long);

    const opt2 = g.next();
    try std.testing.expect(opt2 != null);
    try std.testing.expectEqual(@as(i32, 'f'), opt2.?.opt);
    try std.testing.expectEqualStrings("test.txt", opt2.?.arg.?);
}

test "long option with equals" {
    const long_opts = [_]LongOption{
        .{ .name = "output", .has_arg = .required, .val = 'o' },
    };

    const args = [_][]const u8{ "prog", "--output=result.txt" };
    var g = Getopt.initLong(&args, "o:", &long_opts);

    const opt = g.next();
    try std.testing.expect(opt != null);
    try std.testing.expectEqual(@as(i32, 'o'), opt.?.opt);
    try std.testing.expectEqualStrings("result.txt", opt.?.arg.?);
}

test "remaining args" {
    const args = [_][]const u8{ "prog", "-a", "--", "file1", "file2" };
    var g = Getopt.init(&args, "a");

    _ = g.next(); // -a
    _ = g.next(); // -- terminates

    const rem = g.remaining();
    try std.testing.expectEqual(@as(usize, 2), rem.len);
    try std.testing.expectEqualStrings("file1", rem[0]);
    try std.testing.expectEqualStrings("file2", rem[1]);
}
