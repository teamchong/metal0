/// Core types and helper functions for compile-time evaluation
const std = @import("std");
const ast = @import("../../ast.zig");

/// Check if a list contains only literal values
pub fn isConstantList(list: []ast.Node) bool {
    if (list.len == 0) return false;

    for (list) |elem| {
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements have the same type
pub fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Compile-time value representation
pub const ComptimeValue = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    list: []const ComptimeValue,

    /// Format the value as a string for debugging
    pub fn format(
        self: ComptimeValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .bool => |b| try writer.print("{}", .{b}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .list => |l| {
                try writer.writeAll("[");
                for (l, 0..) |item, idx| {
                    if (idx > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{item});
                }
                try writer.writeAll("]");
            },
        }
    }
};
