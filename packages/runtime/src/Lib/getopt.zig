//! Python 'getopt' module - C-style option parsing
//!
//! Provides functions for parsing command-line options in the style of
//! POSIX getopt() and GNU getopt_long().
//!
//! Mirrors: CPython Lib/getopt.py

const std = @import("std");

pub const GetoptError = error{
    UnknownOption,
    MissingArgument,
    InvalidArgument,
    OutOfMemory,
};

/// Result of getopt parsing
pub const GetoptResult = struct {
    opts: []const struct { opt: []const u8, arg: []const u8 },
    args: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GetoptResult) void {
        self.allocator.free(self.opts);
        self.allocator.free(self.args);
    }
};

/// Parse command-line options (POSIX style)
/// shortopts: String of option characters. Options requiring args have ':' after.
/// Example: "hvo:" means -h, -v (no args), -o (requires arg)
pub fn getopt(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    shortopts: []const u8,
) !GetoptResult {
    return gnu_getopt(allocator, args, shortopts, &[_][]const u8{});
}

/// Parse command-line options (GNU style with long options)
/// longopts: Array of long option strings. Options requiring args end with '='.
/// Example: &.{"help", "verbose", "output="} means --help, --verbose (no args), --output (requires arg)
pub fn gnu_getopt(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    shortopts: []const u8,
    longopts: []const []const u8,
) !GetoptResult {
    var opts = std.ArrayList(struct { opt: []const u8, arg: []const u8 }).init(allocator);
    errdefer opts.deinit();

    var remaining = std.ArrayList([]const u8).init(allocator);
    errdefer remaining.deinit();

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (arg.len == 0 or arg[0] != '-' or std.mem.eql(u8, arg, "-")) {
            // Not an option, add to remaining args
            try remaining.append(arg);
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--")) {
            // End of options
            i += 1;
            while (i < args.len) : (i += 1) {
                try remaining.append(args[i]);
            }
            break;
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            // Long option
            const long_opt = arg[2..];

            // Check if it has embedded =value
            var opt_name: []const u8 = undefined;
            var opt_value: ?[]const u8 = null;
            if (std.mem.indexOf(u8, long_opt, "=")) |eq_pos| {
                opt_name = long_opt[0..eq_pos];
                opt_value = long_opt[eq_pos + 1 ..];
            } else {
                opt_name = long_opt;
            }

            // Find matching long option
            var found = false;
            var requires_arg = false;
            for (longopts) |lo| {
                var base_name = lo;
                if (std.mem.endsWith(u8, lo, "=")) {
                    base_name = lo[0 .. lo.len - 1];
                    if (std.mem.eql(u8, opt_name, base_name)) {
                        requires_arg = true;
                        found = true;
                        break;
                    }
                } else if (std.mem.eql(u8, opt_name, lo)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                return error.UnknownOption;
            }

            if (requires_arg) {
                if (opt_value) |v| {
                    try opts.append(.{ .opt = arg[0 .. 2 + opt_name.len], .arg = v });
                } else if (i + 1 < args.len) {
                    i += 1;
                    try opts.append(.{ .opt = arg, .arg = args[i] });
                } else {
                    return error.MissingArgument;
                }
            } else {
                try opts.append(.{ .opt = arg, .arg = "" });
            }
            i += 1;
        } else {
            // Short option(s)
            var j: usize = 1;
            while (j < arg.len) {
                const c = arg[j];

                // Find in shortopts
                var found = false;
                var requires_arg = false;
                var k: usize = 0;
                while (k < shortopts.len) : (k += 1) {
                    if (shortopts[k] == c) {
                        found = true;
                        if (k + 1 < shortopts.len and shortopts[k + 1] == ':') {
                            requires_arg = true;
                        }
                        break;
                    }
                }

                if (!found) {
                    return error.UnknownOption;
                }

                const opt_str = try std.fmt.allocPrint(allocator, "-{c}", .{c});
                errdefer allocator.free(opt_str);

                if (requires_arg) {
                    // Argument follows immediately or is next arg
                    if (j + 1 < arg.len) {
                        try opts.append(.{ .opt = opt_str, .arg = arg[j + 1 ..] });
                        break; // Rest of arg is the option value
                    } else if (i + 1 < args.len) {
                        i += 1;
                        try opts.append(.{ .opt = opt_str, .arg = args[i] });
                        break;
                    } else {
                        allocator.free(opt_str);
                        return error.MissingArgument;
                    }
                } else {
                    try opts.append(.{ .opt = opt_str, .arg = "" });
                }
                j += 1;
            }
            i += 1;
        }
    }

    return .{
        .opts = try opts.toOwnedSlice(),
        .args = try remaining.toOwnedSlice(),
        .allocator = allocator,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "getopt short options" {
    const allocator = std.testing.allocator;

    var result = try getopt(
        allocator,
        &[_][]const u8{ "-h", "-v", "-o", "output.txt", "file1", "file2" },
        "hvo:",
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.opts.len);
    try std.testing.expectEqualStrings("-h", result.opts[0].opt);
    try std.testing.expectEqualStrings("-v", result.opts[1].opt);
    try std.testing.expectEqualStrings("-o", result.opts[2].opt);
    try std.testing.expectEqualStrings("output.txt", result.opts[2].arg);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("file1", result.args[0]);
}

test "getopt combined short options" {
    const allocator = std.testing.allocator;

    var result = try getopt(
        allocator,
        &[_][]const u8{ "-hv", "file" },
        "hvo:",
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.opts.len);
    try std.testing.expectEqual(@as(usize, 1), result.args.len);
}

test "gnu_getopt long options" {
    const allocator = std.testing.allocator;

    var result = try gnu_getopt(
        allocator,
        &[_][]const u8{ "--help", "--output=test.txt", "file" },
        "ho:",
        &[_][]const u8{ "help", "output=" },
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.opts.len);
    try std.testing.expectEqualStrings("--help", result.opts[0].opt);
    try std.testing.expectEqualStrings("--output", result.opts[1].opt);
    try std.testing.expectEqualStrings("test.txt", result.opts[1].arg);
}

test "getopt double dash" {
    const allocator = std.testing.allocator;

    var result = try getopt(
        allocator,
        &[_][]const u8{ "-h", "--", "-v", "file" },
        "hv",
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.opts.len);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("-v", result.args[0]);
}

test "getopt unknown option" {
    const allocator = std.testing.allocator;

    const result = getopt(
        allocator,
        &[_][]const u8{ "-x" },
        "hv",
    );
    try std.testing.expectError(error.UnknownOption, result);
}

test "getopt missing argument" {
    const allocator = std.testing.allocator;

    const result = getopt(
        allocator,
        &[_][]const u8{ "-o" },
        "o:",
    );
    try std.testing.expectError(error.MissingArgument, result);
}
