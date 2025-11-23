const std = @import("std");
const mvzr = @import("src/mvzr.zig");

pub fn main() !void {
    // Example 1: Basic matching
    const digit_regex = mvzr.compile("[0-9]+") orelse return error.InvalidPattern;

    if (digit_regex.match("abc123def")) |m| {
        std.debug.print("Found digits: {s}\n", .{m.slice});
    }

    // Example 2: Word boundaries
    const word_regex = mvzr.compile("\\bzig\\b") orelse return error.InvalidPattern;
    std.debug.print("Matches 'zig': {}\n", .{word_regex.isMatch("zig rocks")});
    std.debug.print("Matches 'zigging': {}\n", .{word_regex.isMatch("zigging")});

    // Example 3: Iterate all matches
    const num_regex = mvzr.compile("\\d+") orelse return error.InvalidPattern;
    var it = num_regex.iterator("1 22 333 4444");
    std.debug.print("All numbers: ", .{});
    while (it.next()) |m| {
        std.debug.print("{s} ", .{m.slice});
    }
    std.debug.print("\n", .{});

    // Example 4: Email pattern
    const email_regex = mvzr.compile("[a-z]+@[a-z]+\\.[a-z]+") orelse return error.InvalidPattern;
    if (email_regex.match("Contact: user@example.com")) |m| {
        std.debug.print("Email: {s}\n", .{m.slice});
    }
}
