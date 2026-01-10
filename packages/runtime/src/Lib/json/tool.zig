//! json.tool - Command-line tool to validate and pretty-print JSON
//! Reference: cpython/Lib/json/tool.py
//!
//! CPython __all__: main
//!
//! Provides `python -m json.tool` functionality.

const std = @import("std");
const json = @import("../json.zig");

/// Command-line options
pub const Options = struct {
    infile: ?[]const u8 = null,
    outfile: ?[]const u8 = null,
    sort_keys: bool = false,
    no_ensure_ascii: bool = false,
    json_lines: bool = false,
    indent: ?usize = 4,
    tab: bool = false,
    compact: bool = false,
};

/// Parse command line arguments
pub fn parseArgs(args: []const []const u8) Options {
    var opts = Options{};
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--sort-keys") or std.mem.eql(u8, arg, "-s")) {
            opts.sort_keys = true;
        } else if (std.mem.eql(u8, arg, "--no-ensure-ascii")) {
            opts.no_ensure_ascii = true;
        } else if (std.mem.eql(u8, arg, "--json-lines")) {
            opts.json_lines = true;
        } else if (std.mem.eql(u8, arg, "--tab")) {
            opts.tab = true;
        } else if (std.mem.eql(u8, arg, "--compact") or std.mem.eql(u8, arg, "-c")) {
            opts.compact = true;
        } else if (std.mem.eql(u8, arg, "--indent")) {
            if (i + 1 < args.len) {
                i += 1;
                opts.indent = std.fmt.parseInt(usize, args[i], 10) catch 4;
            }
        } else if (arg[0] != '-') {
            if (opts.infile == null) {
                opts.infile = arg;
            } else if (opts.outfile == null) {
                opts.outfile = arg;
            }
        }
    }

    return opts;
}

/// Format JSON with options
pub fn formatJson(allocator: std.mem.Allocator, input: []const u8, opts: Options) ![]const u8 {
    _ = opts;

    // Parse input JSON
    const parsed = json.parse(input, allocator) catch |err| {
        std.debug.print("Error: Invalid JSON - {}\n", .{err});
        return error.InvalidJson;
    };
    defer parsed.deinit(allocator);

    // Stringify with formatting
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    try stringifyValue(allocator, &output, parsed, 0);
    try output.append(allocator, '\n');

    return output.toOwnedSlice(allocator);
}

/// Stringify a JSON value with indentation
fn stringifyValue(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: json.Value, depth: usize) !void {
    const indent = "    ";

    switch (value) {
        .null => try output.appendSlice(allocator, "null"),
        .bool => |b| try output.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
            try output.appendSlice(allocator, str);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch unreachable;
            try output.appendSlice(allocator, str);
        },
        .string => |s| {
            try output.append(allocator, '"');
            for (s) |c| {
                switch (c) {
                    '"' => try output.appendSlice(allocator, "\\\""),
                    '\\' => try output.appendSlice(allocator, "\\\\"),
                    '\n' => try output.appendSlice(allocator, "\\n"),
                    '\r' => try output.appendSlice(allocator, "\\r"),
                    '\t' => try output.appendSlice(allocator, "\\t"),
                    else => try output.append(allocator, c),
                }
            }
            try output.append(allocator, '"');
        },
        .array => |arr| {
            if (arr.items.len == 0) {
                try output.appendSlice(allocator, "[]");
            } else {
                try output.appendSlice(allocator, "[\n");
                for (arr.items, 0..) |item, i| {
                    for (0..depth + 1) |_| try output.appendSlice(allocator, indent);
                    try stringifyValue(allocator, output, item, depth + 1);
                    if (i < arr.items.len - 1) {
                        try output.append(allocator, ',');
                    }
                    try output.append(allocator, '\n');
                }
                for (0..depth) |_| try output.appendSlice(allocator, indent);
                try output.append(allocator, ']');
            }
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try output.appendSlice(allocator, "{}");
            } else {
                try output.appendSlice(allocator, "{\n");
                var iter = obj.iterator();
                var first = true;
                while (iter.next()) |entry| {
                    if (!first) {
                        try output.appendSlice(allocator, ",\n");
                    }
                    first = false;

                    for (0..depth + 1) |_| try output.appendSlice(allocator, indent);
                    try output.append(allocator, '"');
                    try output.appendSlice(allocator, entry.key_ptr.*);
                    try output.appendSlice(allocator, "\": ");
                    try stringifyValue(allocator, output, entry.value_ptr.*, depth + 1);
                }
                try output.append(allocator, '\n');
                for (0..depth) |_| try output.appendSlice(allocator, indent);
                try output.append(allocator, '}');
            }
        },
    }
}

/// Main entry point for json.tool
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    const opts = if (args.len > 1) parseArgs(args[1..]) else Options{};

    // Read input
    const input = if (opts.infile) |path|
        try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize))
    else
        try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input);

    // Format JSON
    const output = try formatJson(allocator, input, opts);
    defer allocator.free(output);

    // Write output
    if (opts.outfile) |path| {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(output);
    } else {
        try std.io.getStdOut().writeAll(output);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parseArgs" {
    const args = [_][]const u8{ "--sort-keys", "--compact", "input.json", "output.json" };
    const opts = parseArgs(&args);

    try std.testing.expect(opts.sort_keys);
    try std.testing.expect(opts.compact);
    try std.testing.expectEqualStrings("input.json", opts.infile.?);
    try std.testing.expectEqualStrings("output.json", opts.outfile.?);
}

test "Options defaults" {
    const opts = Options{};
    try std.testing.expect(!opts.sort_keys);
    try std.testing.expect(!opts.compact);
    try std.testing.expectEqual(@as(?usize, 4), opts.indent);
}
