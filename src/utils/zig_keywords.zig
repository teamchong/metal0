/// Zig reserved keywords and identifier escaping
///
/// When generating Zig code from Python, we must escape identifiers
/// that collide with Zig keywords using @"name" syntax.
const std = @import("std");

/// Zig reserved keywords that cannot be used as identifiers
/// Reference: https://ziglang.org/documentation/master/#Keywords
const zig_keywords = std.StaticStringMap(void).initComptime(.{
    // Control flow
    .{ "if", {} },
    .{ "else", {} },
    .{ "while", {} },
    .{ "for", {} },
    .{ "switch", {} },
    .{ "break", {} },
    .{ "continue", {} },
    .{ "return", {} },
    .{ "defer", {} },
    .{ "errdefer", {} },

    // Functions and types
    .{ "fn", {} },
    .{ "pub", {} },
    .{ "const", {} },
    .{ "var", {} },
    .{ "struct", {} },
    .{ "enum", {} },
    .{ "union", {} },
    .{ "error", {} },
    .{ "opaque", {} },

    // Type keywords
    .{ "type", {} },
    .{ "anytype", {} },
    .{ "anyframe", {} },
    .{ "noreturn", {} },
    .{ "void", {} },
    .{ "unreachable", {} },
    .{ "null", {} },
    .{ "undefined", {} },
    .{ "true", {} },
    .{ "false", {} },

    // Memory and async
    .{ "async", {} },
    .{ "await", {} },
    .{ "suspend", {} },
    .{ "resume", {} },
    .{ "nosuspend", {} },

    // Other reserved
    .{ "and", {} },
    .{ "or", {} },
    .{ "orelse", {} },
    .{ "catch", {} },
    .{ "try", {} },
    .{ "test", {} }, // This is the one causing our issue!
    .{ "inline", {} },
    .{ "comptime", {} },
    .{ "volatile", {} },
    .{ "align", {} },
    .{ "allowzero", {} },
    .{ "linksection", {} },
    .{ "threadlocal", {} },
    .{ "export", {} },
    .{ "extern", {} },
    .{ "packed", {} },
    .{ "usingnamespace", {} },
    .{ "asm", {} },
    .{ "callconv", {} },
    .{ "noalias", {} },
    .{ "noinline", {} },
    .{ "addrspace", {} },
});

/// Check if identifier is a Zig reserved keyword
pub fn isZigKeyword(name: []const u8) bool {
    return zig_keywords.has(name);
}

/// Escape identifier if it's a Zig keyword
/// Returns @"name" for keywords, name otherwise
/// Caller must free returned slice if it was allocated
pub fn escapeIfKeyword(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (!isZigKeyword(name)) {
        return name;
    }
    // Escape as @"name"
    const escaped = try std.fmt.allocPrint(allocator, "@\"{s}\"", .{name});
    return escaped;
}

/// Write escaped identifier to writer
/// This avoids allocation by writing directly
pub fn writeEscapedIdent(writer: anytype, name: []const u8) !void {
    if (isZigKeyword(name)) {
        try writer.print("@\"{s}\"", .{name});
    } else {
        try writer.writeAll(name);
    }
}

test "isZigKeyword" {
    try std.testing.expect(isZigKeyword("test"));
    try std.testing.expect(isZigKeyword("fn"));
    try std.testing.expect(isZigKeyword("const"));
    try std.testing.expect(!isZigKeyword("foo"));
    try std.testing.expect(!isZigKeyword("myFunction"));
}

test "escapeIfKeyword" {
    const allocator = std.testing.allocator;

    // Non-keyword: returns original
    const foo = try escapeIfKeyword(allocator, "foo");
    try std.testing.expectEqualStrings("foo", foo);

    // Keyword: returns escaped
    const t = try escapeIfKeyword(allocator, "test");
    defer allocator.free(t);
    try std.testing.expectEqualStrings("@\"test\"", t);
}
