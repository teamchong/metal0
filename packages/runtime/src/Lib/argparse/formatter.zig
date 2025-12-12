//! Help formatting functions
//!
//! Provides functions to print and format help messages.

const std = @import("std");

// Forward declare ArgumentParser to avoid circular dependency
// The actual type will be provided by the caller
pub fn printHelp(parser: anytype) void {
    const writer = std.io.getStdOut().writer();

    // Usage
    writer.print("usage: {s}", .{parser.prog orelse "prog"}) catch {};
    for (parser.arguments.items) |arg| {
        if (!arg.isPositional()) {
            writer.print(" [{s}]", .{arg.names[0]}) catch {};
        }
    }
    for (parser.arguments.items) |arg| {
        if (arg.isPositional()) {
            writer.print(" {s}", .{arg.getDest()}) catch {};
        }
    }
    writer.print("\n\n", .{}) catch {};

    // Description
    if (parser.description) |desc| {
        writer.print("{s}\n\n", .{desc}) catch {};
    }

    // Positional arguments
    var has_positional = false;
    for (parser.arguments.items) |arg| {
        if (arg.isPositional()) {
            if (!has_positional) {
                writer.print("positional arguments:\n", .{}) catch {};
                has_positional = true;
            }
            writer.print("  {s: <20}", .{arg.getDest()}) catch {};
            if (arg.help) |h| {
                writer.print(" {s}", .{h}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }
    }

    // Optional arguments
    writer.print("\noptions:\n", .{}) catch {};
    for (parser.arguments.items) |arg| {
        if (!arg.isPositional()) {
            var name_buf: [64]u8 = undefined;
            var name_len: usize = 0;
            for (arg.names, 0..) |name, j| {
                if (j > 0) {
                    name_buf[name_len] = ',';
                    name_buf[name_len + 1] = ' ';
                    name_len += 2;
                }
                @memcpy(name_buf[name_len .. name_len + name.len], name);
                name_len += name.len;
            }
            writer.print("  {s: <20}", .{name_buf[0..name_len]}) catch {};
            if (arg.help) |h| {
                writer.print(" {s}", .{h}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }
    }

    // Epilog
    if (parser.epilog) |ep| {
        writer.print("\n{s}\n", .{ep}) catch {};
    }
}

/// Format help as string
pub fn formatHelp(parser: anytype, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "usage: ");
    try result.appendSlice(allocator, parser.prog orelse "prog");

    for (parser.arguments.items) |arg| {
        if (!arg.isPositional()) {
            try result.appendSlice(allocator, " [");
            try result.appendSlice(allocator, arg.names[0]);
            try result.append(allocator, ']');
        }
    }

    try result.append(allocator, '\n');

    if (parser.description) |desc| {
        try result.append(allocator, '\n');
        try result.appendSlice(allocator, desc);
        try result.append(allocator, '\n');
    }

    return result.toOwnedSlice(allocator);
}
